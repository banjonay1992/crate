import Foundation
@testable import CrateCore

/// Decoded fixtures as domain models.
enum Fixtures {
    static func release(_ id: Int) -> Release {
        try! JSONDecoder().decode(DiscogsDTO.Release.self, from: Fixture.data("release_\(id)")).toDomain()
    }

    static func searchResults(_ name: String) -> [ReleaseSummary] {
        try! JSONDecoder().decode(DiscogsDTO.SearchPage.self, from: Fixture.data(name)).results.map { $0.toDomain() }
    }

    static var collection: [CollectionItem] {
        ["collection_page1", "collection_page2"].flatMap { name in
            try! JSONDecoder().decode(DiscogsDTO.CollectionPage.self, from: Fixture.data(name)).releases.map {
                CollectionItem(instanceID: $0.instanceID, folderID: $0.folderID ?? 0, dateAdded: DiscogsDTO.date($0.dateAdded), rating: $0.rating ?? 0, release: $0.basicInformation.toDomain())
            }
        }
    }

    static var wants: [Want] {
        try! JSONDecoder().decode(DiscogsDTO.WantsPage.self, from: Fixture.data("wants_page1")).wants.map {
            Want(release: $0.basicInformation.toDomain(), dateAdded: DiscogsDTO.date($0.dateAdded), notes: $0.notes, rating: $0.rating ?? 0)
        }
    }
}
