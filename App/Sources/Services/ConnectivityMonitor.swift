import Foundation
import Network

/// Watches the network path so Crate can show an offline banner and drain the
/// lookup queue as soon as a connection comes back.
final class ConnectivityMonitor: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "uk.co.nayproductions.crate.connectivity")

    /// Called on the main actor whenever reachability changes.
    func start(onChange: @escaping @MainActor @Sendable (Bool) -> Void) {
        monitor.pathUpdateHandler = { path in
            let online = path.status == .satisfied
            Task { @MainActor in onChange(online) }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
    }
}
