import Network
import Foundation

/// Watches general network reachability and calls back when the path
/// transitions from unreachable to reachable, so the dashboard can trigger
/// a reload as soon as the network comes back (e.g. after a Wi-Fi outage).
final class ConnectivityMonitor {

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.hakiosk.app.connectivity")
    private var wasSatisfied = true

    var onBecameReachable: (() -> Void)?
    var onBecameUnreachable: (() -> Void)?

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            let isSatisfied = path.status == .satisfied
            DispatchQueue.main.async {
                if isSatisfied && !self.wasSatisfied {
                    self.onBecameReachable?()
                } else if !isSatisfied && self.wasSatisfied {
                    self.onBecameUnreachable?()
                }
                self.wasSatisfied = isSatisfied
            }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
    }
}
