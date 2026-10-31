import Foundation

/// The signed-in Discogs user, from `GET /oauth/identity`.
public struct UserIdentity: Codable, Hashable, Sendable {
    public var id: Int
    public var username: String

    public init(id: Int, username: String) {
        self.id = id
        self.username = username
    }
}

/// One copy of a release in the user's collection. A user can own several
/// copies of the same release, each with its own instance id.
public struct CollectionItem: Codable, Hashable, Sendable, Identifiable {
    public var instanceID: Int
    public var folderID: Int
    public var dateAdded: Date?
    public var rating: Int
    public var release: ReleaseSummary

    public var id: Int { instanceID }
    public var releaseID: ReleaseID { release.id }

    public init(instanceID: Int, folderID: Int = 1, dateAdded: Date? = nil, rating: Int = 0, release: ReleaseSummary) {
        self.instanceID = instanceID
        self.folderID = folderID
        self.dateAdded = dateAdded
        self.rating = rating
        self.release = release
    }
}

/// One entry on the user's wantlist.
public struct Want: Codable, Hashable, Sendable, Identifiable {
    public var release: ReleaseSummary
    public var dateAdded: Date?
    public var notes: String?
    public var rating: Int

    public var id: ReleaseID { release.id }
    public var releaseID: ReleaseID { release.id }

    public init(release: ReleaseSummary, dateAdded: Date? = nil, notes: String? = nil, rating: Int = 0) {
        self.release = release
        self.dateAdded = dateAdded
        self.notes = notes
        self.rating = rating
    }
}

/// One page of a paginated Discogs listing.
public struct Page<Item: Sendable>: Sendable {
    public var items: [Item]
    public var page: Int
    public var pages: Int
    public var perPage: Int
    public var totalItems: Int

    public init(items: [Item], page: Int, pages: Int, perPage: Int, totalItems: Int) {
        self.items = items
        self.page = page
        self.pages = pages
        self.perPage = perPage
        self.totalItems = totalItems
    }

    public var hasNextPage: Bool { page < pages }
}

extension Page: Equatable where Item: Equatable {}
