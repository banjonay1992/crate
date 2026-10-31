import Foundation

/// What the user is looking up.
public enum LookupQuery: Codable, Hashable, Sendable {
    case barcode(Barcode)
    case catalogueNumber(String)
    case matrix(String)

    public enum Kind: String, Codable, CaseIterable, Sendable {
        case barcode
        case catalogueNumber
        case matrix

        public var displayName: String {
            switch self {
            case .barcode: "Barcode"
            case .catalogueNumber: "Cat. no."
            case .matrix: "Matrix / run-out"
            }
        }
    }

    public var kind: Kind {
        switch self {
        case .barcode: .barcode
        case .catalogueNumber: .catalogueNumber
        case .matrix: .matrix
        }
    }

    /// The text shown back to the user.
    public var displayText: String {
        switch self {
        case .barcode(let barcode): barcode.digits
        case .catalogueNumber(let text), .matrix(let text): text
        }
    }

    /// Builds a query from typed text for an explicit kind. Returns nil if the
    /// text is too short to be useful or is not a valid barcode.
    public static func make(kind: Kind, text: String) -> LookupQuery? {
        let trimmed = IdentifierNormaliser.tidy(text)
        switch kind {
        case .barcode:
            guard let barcode = Barcode(trimmed) else { return nil }
            return .barcode(barcode)
        case .catalogueNumber:
            guard IdentifierNormaliser.catalogueKey(trimmed).count >= 2 else { return nil }
            return .catalogueNumber(trimmed)
        case .matrix:
            guard IdentifierNormaliser.matrixKey(trimmed).count >= 3 else { return nil }
            return .matrix(trimmed)
        }
    }

    /// Guesses the kind for free text: a valid 8, 12 or 13 digit code is a
    /// barcode, anything else is treated as a catalogue number. Matrix numbers
    /// look too much like catalogue numbers to guess, so the user picks that.
    public static func infer(from text: String) -> LookupQuery? {
        let trimmed = IdentifierNormaliser.tidy(text)
        if let barcode = Barcode(trimmed), barcode.hasValidCheckDigit {
            return .barcode(barcode)
        }
        return make(kind: .catalogueNumber, text: trimmed)
    }
}

/// Text normalisation for catalogue numbers and matrix / run-out strings.
///
/// People type these inconsistently ("GCR-012", "gcr 012", "GCR012") and Discogs
/// contributors transcribe etchings in their own way, so comparisons are made
/// on reduced keys rather than the raw text.
public enum IdentifierNormaliser {
    /// Trims, collapses runs of whitespace and replaces typographic dashes.
    public static func tidy(_ text: String) -> String {
        let replaced = text
            .replacingOccurrences(of: "\u{2013}", with: "-")
            .replacingOccurrences(of: "\u{2014}", with: "-")
            .replacingOccurrences(of: "\u{2212}", with: "-")
        return replaced
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// Upper-cased, accent-folded, alphanumerics only. "gcr-012" and "GCR 012" both become "GCR012".
    public static func catalogueKey(_ text: String) -> String {
        alphanumericKey(text)
    }

    /// Like `catalogueKey` but with leading zeros removed from each run of digits,
    /// so "GCR 12" and "GCR 012" compare equal. Used as a weaker, second-tier match.
    public static func looseCatalogueKey(_ text: String) -> String {
        var result = ""
        var digitRun = ""
        func flushDigits() {
            guard !digitRun.isEmpty else { return }
            let trimmed = digitRun.drop { $0 == "0" }
            result += trimmed.isEmpty ? "0" : String(trimmed)
            digitRun = ""
        }
        for character in alphanumericKey(text) {
            if character.isASCIIDigit {
                digitRun.append(character)
            } else {
                flushDigits()
                result.append(character)
            }
        }
        flushDigits()
        return result
    }

    /// Key for matrix / run-out comparisons. Etched symbols, spaces and
    /// punctuation are dropped; a slashed zero is read as a zero.
    public static func matrixKey(_ text: String) -> String {
        let mapped = text
            .replacingOccurrences(of: "Ø", with: "0")
            .replacingOccurrences(of: "ø", with: "0")
        return alphanumericKey(mapped)
    }

    /// Tokens for matrix comparisons: alphanumeric runs, upper-cased.
    public static func matrixTokens(_ text: String) -> [String] {
        let folded = fold(text.replacingOccurrences(of: "Ø", with: "0").replacingOccurrences(of: "ø", with: "0"))
        var tokens: [String] = []
        var current = ""
        for scalar in folded.unicodeScalars {
            if scalar.isASCIIAlphanumeric {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_GB"))
            .uppercased()
    }

    static func alphanumericKey(_ text: String) -> String {
        String(String.UnicodeScalarView(fold(text).unicodeScalars.filter(\.isASCIIAlphanumeric)))
    }
}

extension Unicode.Scalar {
    var isASCIIAlphanumeric: Bool {
        ("0"..."9").contains(self) || ("A"..."Z").contains(self) || ("a"..."z").contains(self)
    }
}
