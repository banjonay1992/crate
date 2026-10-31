import Foundation

// Wire formats for the Discogs API. These mirror the JSON the API returns and
// are converted to the domain models straight after decoding, so the rest of
// the code never depends on Discogs naming. Discogs is not always consistent
// (year is a number in one endpoint and a string in another, many fields are
// optional), so decoding here is deliberately lenient.

enum DiscogsDTO {
    struct Pagination: Decodable {
        let page: Int
        let pages: Int
        let perPage: Int
        let items: Int

        enum CodingKeys: String, CodingKey {
            case page, pages, items
            case perPage = "per_page"
        }
    }

    struct Identity: Decodable {
        let id: Int
        let username: String
    }

    struct Artist: Decodable {
        let name: String
        let anv: String?
        let join: String?
    }

    struct Label: Decodable {
        let name: String
        let catno: String?
    }

    struct Format: Decodable {
        let name: String
        let qty: String?
        let descriptions: [String]?
        let text: String?
    }

    struct Identifier: Decodable {
        let type: String
        let value: String
        let description: String?
    }

    struct TrackDTO: Decodable {
        let position: String?
        let title: String
        let duration: String?
        let type: String?

        enum CodingKeys: String, CodingKey {
            case position, title, duration
            case type = "type_"
        }
    }

    struct Community: Decodable {
        let have: Int?
        let want: Int?
    }

    struct Release: Decodable {
        let id: Int
        let masterID: Int?
        let title: String
        let artists: [Artist]?
        let year: LenientInt?
        let country: String?
        let released: String?
        let labels: [Label]?
        let formats: [Format]?
        let identifiers: [Identifier]?
        let tracklist: [TrackDTO]?
        let thumb: String?
        let uri: String?
        let community: Community?
        let lowestPrice: Double?
        let numForSale: Int?

        enum CodingKeys: String, CodingKey {
            case id, title, artists, year, country, released, labels, formats, identifiers, tracklist, thumb, uri, community
            case masterID = "master_id"
            case lowestPrice = "lowest_price"
            case numForSale = "num_for_sale"
        }
    }

    /// `basic_information` inside collection and wantlist entries.
    struct BasicInformation: Decodable {
        let id: Int
        let masterID: Int?
        let title: String
        let year: LenientInt?
        let thumb: String?
        let formats: [Format]?
        let labels: [Label]?
        let artists: [Artist]?

        enum CodingKeys: String, CodingKey {
            case id, title, year, thumb, formats, labels, artists
            case masterID = "master_id"
        }
    }

    struct CollectionRelease: Decodable {
        let id: Int
        let instanceID: Int
        let folderID: Int?
        let rating: Int?
        let dateAdded: String?
        let basicInformation: BasicInformation

        enum CodingKeys: String, CodingKey {
            case id, rating
            case instanceID = "instance_id"
            case folderID = "folder_id"
            case dateAdded = "date_added"
            case basicInformation = "basic_information"
        }
    }

    struct CollectionPage: Decodable {
        let pagination: Pagination
        let releases: [CollectionRelease]
    }

    struct WantDTO: Decodable {
        let id: Int
        let rating: Int?
        let notes: String?
        let dateAdded: String?
        let basicInformation: BasicInformation

        enum CodingKeys: String, CodingKey {
            case id, rating, notes
            case dateAdded = "date_added"
            case basicInformation = "basic_information"
        }
    }

    struct WantsPage: Decodable {
        let pagination: Pagination
        let wants: [WantDTO]
    }

    struct SearchResult: Decodable {
        let id: Int
        let type: String?
        let masterID: Int?
        let title: String
        let year: LenientInt?
        let country: String?
        let format: [String]?
        let label: [String]?
        let catno: String?
        let barcode: [String]?
        let thumb: String?
        let formatQuantity: Int?

        enum CodingKeys: String, CodingKey {
            case id, type, title, year, country, format, label, catno, barcode, thumb
            case masterID = "master_id"
            case formatQuantity = "format_quantity"
        }
    }

    struct SearchPage: Decodable {
        let pagination: Pagination
        let results: [SearchResult]
    }

    struct Price: Decodable {
        let currency: String
        let value: Double
    }

    struct MarketplaceStats: Decodable {
        let lowestPrice: Price?
        let numForSale: Int?
        let blockedFromSale: Bool?

        enum CodingKeys: String, CodingKey {
            case lowestPrice = "lowest_price"
            case numForSale = "num_for_sale"
            case blockedFromSale = "blocked_from_sale"
        }
    }

    struct ErrorBody: Decodable {
        let message: String
    }

    /// `GET /marketplace/price_suggestions/{id}` returns an object keyed by
    /// condition name. Unknown keys are ignored.
    static func priceSuggestions(from data: Data, decoder: JSONDecoder) throws -> [PricePoint] {
        let raw = try decoder.decode([String: Price].self, from: data)
        return raw.compactMap { key, price in
            guard let condition = MediaCondition(rawValue: key) else { return nil }
            return PricePoint(condition: condition, price: Money(value: price.value, currency: price.currency))
        }
        .sorted { $0.condition < $1.condition }
    }
}

/// Decodes an integer that might arrive as a number, a numeric string, or an empty string.
struct LenientInt: Decodable {
    let value: Int?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = nil
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let string = try? container.decode(String.self) {
            value = Int(string.trimmingCharacters(in: .whitespaces))
        } else if let double = try? container.decode(Double.self) {
            value = Int(double)
        } else {
            value = nil
        }
    }
}

// MARK: - Mapping to domain models

extension DiscogsDTO {
    /// Discogs disambiguates artists with the same name by appending " (2)", " (3)"
    /// and so on. That suffix is noise on a phone screen, so it is removed.
    static func cleanArtistName(_ name: String) -> String {
        guard name.hasSuffix(")"), let open = name.lastIndex(of: "(") else { return name }
        let inside = name[name.index(after: open)..<name.index(before: name.endIndex)]
        guard !inside.isEmpty, inside.allSatisfy(\.isNumber) else { return name }
        return name[..<open].trimmingCharacters(in: .whitespaces)
    }

    /// Joins artist credits the way Discogs displays them, honouring the
    /// `anv` (artist name variation) and `join` fields.
    static func artistDisplay(_ artists: [Artist]?) -> String {
        guard let artists, !artists.isEmpty else { return "" }
        var result = ""
        for (index, artist) in artists.enumerated() {
            let name = (artist.anv?.isEmpty == false ? artist.anv! : cleanArtistName(artist.name))
            result += name
            if index < artists.count - 1 {
                let join = (artist.join ?? "").trimmingCharacters(in: .whitespaces)
                switch join {
                case "", ",": result += join.isEmpty ? " & " : ", "
                default: result += " \(join) "
                }
            }
        }
        return result
    }

    static func url(_ string: String?) -> URL? {
        guard let string, !string.isEmpty else { return nil }
        return URL(string: string)
    }

    static func webURL(_ uri: String?) -> URL? {
        guard let uri, !uri.isEmpty else { return nil }
        if uri.hasPrefix("http") { return URL(string: uri) }
        return URL(string: "https://www.discogs.com" + (uri.hasPrefix("/") ? uri : "/" + uri))
    }

    /// Discogs uses 0 for an unknown year.
    static func year(_ lenient: LenientInt?) -> Int? {
        guard let value = lenient?.value, value > 0 else { return nil }
        return value
    }

    static func date(_ string: String?) -> Date? {
        guard let string else { return nil }
        return try? Date(string, strategy: .iso8601)
    }

    static func labels(_ labels: [Label]?) -> [LabelCredit] {
        (labels ?? []).map { label in
            // Discogs uses "none" as a catalogue number placeholder.
            let catno = (label.catno ?? "").trimmingCharacters(in: .whitespaces)
            return LabelCredit(
                name: cleanArtistName(label.name),
                catalogueNumber: catno.lowercased() == "none" ? "" : catno
            )
        }
    }

    static func formats(_ formats: [Format]?) -> [FormatDescriptor] {
        (formats ?? []).map {
            FormatDescriptor(
                name: $0.name,
                quantity: Int($0.qty ?? "1") ?? 1,
                descriptions: $0.descriptions ?? [],
                text: ($0.text?.isEmpty == false) ? $0.text : nil
            )
        }
    }
}

extension DiscogsDTO.Release {
    func toDomain() -> Release {
        Release(
            id: id,
            masterID: (masterID ?? 0) > 0 ? masterID : nil,
            title: title,
            artist: DiscogsDTO.artistDisplay(artists),
            year: DiscogsDTO.year(year),
            country: country,
            released: released,
            labels: DiscogsDTO.labels(labels),
            formats: DiscogsDTO.formats(formats),
            identifiers: (identifiers ?? []).map {
                ReleaseIdentifier(type: $0.type, value: $0.value, detail: ($0.description?.isEmpty == false) ? $0.description : nil)
            },
            tracklist: (tracklist ?? [])
                .filter { $0.type == nil || $0.type == "track" }
                .map { Track(position: $0.position ?? "", title: $0.title, duration: ($0.duration?.isEmpty == false) ? $0.duration : nil) },
            thumbURL: DiscogsDTO.url(thumb),
            webURL: DiscogsDTO.webURL(uri),
            community: community.map { CommunityStats(have: $0.have ?? 0, want: $0.want ?? 0) },
            lowestPrice: lowestPrice,
            numForSale: numForSale
        )
    }
}

extension DiscogsDTO.BasicInformation {
    func toDomain() -> ReleaseSummary {
        ReleaseSummary(
            id: id,
            masterID: (masterID ?? 0) > 0 ? masterID : nil,
            title: title,
            artist: DiscogsDTO.artistDisplay(artists),
            year: DiscogsDTO.year(year),
            country: nil,
            labels: DiscogsDTO.labels(labels),
            formats: DiscogsDTO.formats(formats),
            thumbURL: DiscogsDTO.url(thumb),
            barcodes: []
        )
    }
}

extension DiscogsDTO.SearchResult {
    func toDomain() -> ReleaseSummary {
        // Search titles are "Artist - Title". Split on the first " - " only,
        // because titles themselves can contain dashes.
        var artist = ""
        var releaseTitle = title
        if let range = title.range(of: " - ") {
            artist = DiscogsDTO.cleanArtistName(String(title[..<range.lowerBound]))
            releaseTitle = String(title[range.upperBound...])
        }
        let formatNames = format ?? []
        let formatsList: [FormatDescriptor] = formatNames.isEmpty
            ? []
            : [FormatDescriptor(name: formatNames[0], quantity: formatQuantity ?? 1, descriptions: Array(formatNames.dropFirst()))]
        let catno = (catno ?? "").lowercased() == "none" ? "" : (catno ?? "")
        let labelsList: [LabelCredit] = (label ?? []).prefix(1).map { LabelCredit(name: $0, catalogueNumber: catno) }
        return ReleaseSummary(
            id: id,
            masterID: (masterID ?? 0) > 0 ? masterID : nil,
            title: releaseTitle,
            artist: artist,
            year: DiscogsDTO.year(year),
            country: country,
            labels: labelsList,
            formats: formatsList,
            thumbURL: DiscogsDTO.url(thumb),
            barcodes: barcode ?? []
        )
    }
}

extension DiscogsDTO.MarketplaceStats {
    func toDomain() -> MarketplaceStats {
        MarketplaceStats(
            lowestPrice: lowestPrice.map { Money(value: $0.value, currency: $0.currency) },
            numForSale: numForSale,
            blockedFromSale: blockedFromSale ?? false
        )
    }
}

extension DiscogsDTO.Pagination {
    func page<Item>(_ items: [Item]) -> Page<Item> {
        Page(items: items, page: page, pages: max(pages, 1), perPage: perPage, totalItems: self.items)
    }
}
