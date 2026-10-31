import Foundation

/// The barcode symbologies found on record sleeves.
public enum BarcodeSymbology: String, Codable, Hashable, Sendable {
    /// 13 digits. Standard outside North America.
    case ean13
    /// 8 digits. Rare on records but it turns up on singles.
    case ean8
    /// 12 digits. Standard in the US and Canada.
    case upcA
    /// 8 digit zero-suppressed UPC, expanded to UPC-A for lookup.
    case upcE
}

/// A validated retail barcode.
///
/// Discogs stores barcodes exactly as they are printed ("5 012345 600123",
/// "0 73311 22445 8"), and the same product can be written as 12-digit UPC-A or
/// 13-digit EAN-13 with a leading zero. `Barcode` reduces all of those to one
/// canonical digit string so that comparisons are reliable.
public struct Barcode: Codable, Hashable, Sendable {
    /// Digits as entered or scanned, with separators removed.
    public let digits: String
    public let symbology: BarcodeSymbology

    /// Parses free text. Spaces, hyphens and dots are ignored. Returns nil if what
    /// is left is not 8, 12 or 13 digits.
    ///
    /// Eight digits are read as EAN-8. A scanner that knows it saw UPC-E should
    /// use `init?(upcE:)` instead, because the two cannot be told apart from the
    /// digits alone.
    public init?(_ text: String) {
        let digits = Self.stripSeparators(text)
        guard !digits.isEmpty, digits.allSatisfy(\.isASCIIDigit) else { return nil }
        switch digits.count {
        case 13: self.init(digits: digits, symbology: .ean13)
        case 12: self.init(digits: digits, symbology: .upcA)
        case 8: self.init(digits: digits, symbology: .ean8)
        default: return nil
        }
    }

    /// Parses an 8-digit UPC-E code (number system, six data digits, check digit).
    /// Some scanners drop the number system and give 7 digits; a leading 0 is assumed then.
    public init?(upcE text: String) {
        var digits = Self.stripSeparators(text)
        guard digits.allSatisfy(\.isASCIIDigit) else { return nil }
        if digits.count == 7 { digits = "0" + digits }
        guard digits.count == 8, digits.first == "0" || digits.first == "1" else { return nil }
        self.init(digits: digits, symbology: .upcE)
    }

    private init(digits: String, symbology: BarcodeSymbology) {
        self.digits = digits
        self.symbology = symbology
    }

    /// True if the final digit matches the GS1 check digit for the rest.
    public var hasValidCheckDigit: Bool {
        switch symbology {
        case .upcE:
            guard let expanded = Self.expandUPCE(digits) else { return false }
            return Self.checkDigitIsValid(expanded)
        default:
            return Self.checkDigitIsValid(digits)
        }
    }

    /// The form used for comparisons: EAN-13 for anything in the UPC/EAN-13
    /// family, the original 8 digits for EAN-8.
    public var canonical: String {
        switch symbology {
        case .ean13: digits
        case .upcA: "0" + digits
        case .ean8: digits
        case .upcE: Self.expandUPCE(digits).map { "0" + $0 } ?? digits
        }
    }

    /// Forms worth sending to a search, most likely first. Discogs search does
    /// not treat UPC-A and EAN-13 as the same, so both are tried.
    public var searchVariants: [String] {
        var variants: [String] = []
        func add(_ value: String) { if !variants.contains(value) { variants.append(value) } }
        switch symbology {
        case .ean13:
            add(digits)
            if digits.hasPrefix("0") { add(String(digits.dropFirst())) }
        case .upcA:
            add(digits)
            add("0" + digits)
        case .ean8:
            add(digits)
        case .upcE:
            if let expanded = Self.expandUPCE(digits) {
                add(expanded)
                add("0" + expanded)
            }
            add(digits)
        }
        return variants
    }

    /// Canonical key for any string that might be a barcode as Discogs prints it.
    /// Returns nil for strings that are not barcodes (matrix numbers often sit
    /// in the same list in search results).
    public static func canonicalKey(for text: String) -> String? {
        Barcode(text)?.canonical
    }

    // MARK: - Helpers

    static func stripSeparators(_ text: String) -> String {
        String(text.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) && $0 != "-" && $0 != "." })
    }

    /// GS1 check digit test. Works for EAN-8, UPC-A and EAN-13: weights of 3 and 1
    /// alternate from the digit nearest the check digit.
    static func checkDigitIsValid(_ digits: String) -> Bool {
        let values = digits.compactMap(\.wholeNumberValue)
        guard values.count == digits.count, values.count >= 2, let check = values.last else { return false }
        return computeCheckDigit(Array(values.dropLast())) == check
    }

    static func computeCheckDigit(_ body: [Int]) -> Int {
        var sum = 0
        for (offset, value) in body.reversed().enumerated() {
            sum += value * (offset.isMultiple(of: 2) ? 3 : 1)
        }
        return (10 - sum % 10) % 10
    }

    /// Expands an 8-digit UPC-E code to its 12-digit UPC-A equivalent.
    static func expandUPCE(_ upcE: String) -> String? {
        let d = upcE.compactMap(\.wholeNumberValue)
        guard d.count == 8 else { return nil }
        let numberSystem = d[0]
        let data = Array(d[1...6])
        let check = d[7]
        let manufacturer: [Int]
        let product: [Int]
        switch data[5] {
        case 0, 1, 2:
            manufacturer = [data[0], data[1], data[5], 0, 0]
            product = [0, 0, data[2], data[3], data[4]]
        case 3:
            manufacturer = [data[0], data[1], data[2], 0, 0]
            product = [0, 0, 0, data[3], data[4]]
        case 4:
            manufacturer = [data[0], data[1], data[2], data[3], 0]
            product = [0, 0, 0, 0, data[4]]
        default:
            manufacturer = [data[0], data[1], data[2], data[3], data[4]]
            product = [0, 0, 0, 0, data[5]]
        }
        let all = [numberSystem] + manufacturer + product + [check]
        return all.map(String.init).joined()
    }
}

extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}
