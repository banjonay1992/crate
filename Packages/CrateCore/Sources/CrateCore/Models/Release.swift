import Foundation

/// Discogs release identifier. A release is one specific pressing or edition.
public typealias ReleaseID = Int

/// Discogs master identifier. A master groups every release of the same album.
public typealias MasterID = Int

/// A label and the catalogue number it gave this release.
public struct LabelCredit: Codable, Hashable, Sendable {
    public var name: String
    public var catalogueNumber: String

    public init(name: String, catalogueNumber: String) {
        self.name = name
        self.catalogueNumber = catalogueNumber
    }
}

/// One format entry, for example "Vinyl, LP, Album, Gatefold".
public struct FormatDescriptor: Codable, Hashable, Sendable {
    public var name: String
    public var quantity: Int
    public var descriptions: [String]
    public var text: String?

    public init(name: String, quantity: Int = 1, descriptions: [String] = [], text: String? = nil) {
        self.name = name
        self.quantity = quantity
        self.descriptions = descriptions
        self.text = text
    }

    /// Human readable form, for example "2 x Vinyl, LP, Album (Gatefold)".
    public var displayText: String {
        var parts = [name] + descriptions
        if quantity > 1 { parts[0] = "\(quantity) x \(name)" }
        var result = parts.joined(separator: ", ")
        if let text, !text.isEmpty { result += " (\(text))" }
        return result
    }
}

/// The kinds of identifier Crate cares about. Discogs has many more; they are kept as `other`.
public enum IdentifierKind: Hashable, Sendable {
    case barcode
    case matrixRunout
    case labelCode
    case other(String)

    public init(discogsType: String) {
        switch discogsType.lowercased() {
        case "barcode": self = .barcode
        case "matrix / runout", "matrix/runout", "runout", "matrix": self = .matrixRunout
        case "label code": self = .labelCode
        default: self = .other(discogsType)
        }
    }
}

/// An identifier printed on a release: barcode, matrix / run-out etching, and so on.
public struct ReleaseIdentifier: Codable, Hashable, Sendable {
    /// The type string exactly as Discogs gives it, for example "Matrix / Runout".
    public var type: String
    public var value: String
    /// Free text such as "Side A" or "Text". Optional.
    public var detail: String?

    public init(type: String, value: String, detail: String? = nil) {
        self.type = type
        self.value = value
        self.detail = detail
    }

    public var kind: IdentifierKind { IdentifierKind(discogsType: type) }
}

public struct Track: Codable, Hashable, Sendable {
    public var position: String
    public var title: String
    public var duration: String?

    public init(position: String, title: String, duration: String? = nil) {
        self.position = position
        self.title = title
        self.duration = duration
    }
}

/// Community counts from Discogs: how many users have and want a release.
public struct CommunityStats: Codable, Hashable, Sendable {
    public var have: Int
    public var want: Int

    public init(have: Int, want: Int) {
        self.have = have
        self.want = want
    }
}

/// The lightweight description of a release that appears in search results,
/// collection entries and wantlist entries.
public struct ReleaseSummary: Codable, Hashable, Sendable, Identifiable {
    public var id: ReleaseID
    public var masterID: MasterID?
    public var title: String
    public var artist: String
    public var year: Int?
    public var country: String?
    public var labels: [LabelCredit]
    public var formats: [FormatDescriptor]
    public var thumbURL: URL?
    /// Barcodes, when the source provides them (search results do, collection entries do not).
    public var barcodes: [String]

    public init(
        id: ReleaseID,
        masterID: MasterID? = nil,
        title: String,
        artist: String,
        year: Int? = nil,
        country: String? = nil,
        labels: [LabelCredit] = [],
        formats: [FormatDescriptor] = [],
        thumbURL: URL? = nil,
        barcodes: [String] = []
    ) {
        self.id = id
        self.masterID = masterID
        self.title = title
        self.artist = artist
        self.year = year
        self.country = country
        self.labels = labels
        self.formats = formats
        self.thumbURL = thumbURL
        self.barcodes = barcodes
    }

    public var catalogueNumbers: [String] { labels.map(\.catalogueNumber).filter { !$0.isEmpty } }

    /// "Artist - Title"
    public var displayTitle: String { artist.isEmpty ? title : "\(artist) - \(title)" }

    /// Short pressing description, for example "Granite Coast Records GCR 012, UK, 1984".
    public var pressingLine: String {
        var parts: [String] = []
        if let label = labels.first {
            parts.append([label.name, label.catalogueNumber].filter { !$0.isEmpty }.joined(separator: " "))
        }
        if let country, !country.isEmpty { parts.append(country) }
        if let year { parts.append(String(year)) }
        return parts.joined(separator: ", ")
    }
}

/// A full release, as returned by `GET /releases/{id}`.
public struct Release: Codable, Hashable, Sendable, Identifiable {
    public var id: ReleaseID
    public var masterID: MasterID?
    public var title: String
    public var artist: String
    public var year: Int?
    public var country: String?
    public var released: String?
    public var labels: [LabelCredit]
    public var formats: [FormatDescriptor]
    public var identifiers: [ReleaseIdentifier]
    public var tracklist: [Track]
    public var thumbURL: URL?
    public var webURL: URL?
    public var community: CommunityStats?
    public var lowestPrice: Double?
    public var numForSale: Int?

    public init(
        id: ReleaseID,
        masterID: MasterID? = nil,
        title: String,
        artist: String,
        year: Int? = nil,
        country: String? = nil,
        released: String? = nil,
        labels: [LabelCredit] = [],
        formats: [FormatDescriptor] = [],
        identifiers: [ReleaseIdentifier] = [],
        tracklist: [Track] = [],
        thumbURL: URL? = nil,
        webURL: URL? = nil,
        community: CommunityStats? = nil,
        lowestPrice: Double? = nil,
        numForSale: Int? = nil
    ) {
        self.id = id
        self.masterID = masterID
        self.title = title
        self.artist = artist
        self.year = year
        self.country = country
        self.released = released
        self.labels = labels
        self.formats = formats
        self.identifiers = identifiers
        self.tracklist = tracklist
        self.thumbURL = thumbURL
        self.webURL = webURL
        self.community = community
        self.lowestPrice = lowestPrice
        self.numForSale = numForSale
    }

    public var barcodes: [String] { identifiers.filter { $0.kind == .barcode }.map(\.value) }
    public var matrices: [ReleaseIdentifier] { identifiers.filter { $0.kind == .matrixRunout } }
    public var catalogueNumbers: [String] { labels.map(\.catalogueNumber).filter { !$0.isEmpty } }

    public var summary: ReleaseSummary {
        ReleaseSummary(
            id: id,
            masterID: masterID,
            title: title,
            artist: artist,
            year: year,
            country: country,
            labels: labels,
            formats: formats,
            thumbURL: thumbURL,
            barcodes: barcodes
        )
    }
}
