import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum DiscogsError: Error, Hashable, Sendable {
    /// No token has been set up.
    case missingCredentials
    /// 401 or 403: the token is wrong, revoked, or lacks access.
    case unauthorised(message: String?)
    case notFound
    /// Still rate limited after every retry.
    case rateLimited
    case server(status: Int, message: String?)
    /// The device has no usable connection. Lookups are queued when this happens.
    case offline
    case transport(String)
    case decoding(String)

    /// Errors that are worth trying again later from the lookup queue.
    public var isTransient: Bool {
        switch self {
        case .offline, .rateLimited, .transport: true
        case .server(let status, _): status >= 500
        default: false
        }
    }

    public var userMessage: String {
        switch self {
        case .missingCredentials:
            "Connect your Discogs account in Settings to look records up."
        case .unauthorised:
            "Discogs did not accept your token. Check it in Settings."
        case .notFound:
            "Discogs has no record of that."
        case .rateLimited:
            "Discogs asked Crate to slow down. Try again in a minute."
        case .server(let status, _):
            "Discogs had a problem (HTTP \(status)). Try again shortly."
        case .offline:
            "No connection. The lookup has been saved and will run when you are back online."
        case .transport:
            "The request to Discogs failed. Check your connection."
        case .decoding:
            "Discogs sent something Crate did not understand."
        }
    }

    /// Maps a transport-level error onto a Discogs error.
    static func from(transportError error: Error) -> DiscogsError {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost,
                 .cannotConnectToHost, .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff,
                 .callIsActive:
                return .offline
            default:
                return .transport(urlError.localizedDescription)
            }
        }
        return .transport(String(describing: error))
    }
}
