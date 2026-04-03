#if canImport(Network)
    import Foundation
    import Network

    protocol NetworkMonitoring {
        var isConnected: Bool { get }
        var onConnectivityRestored: (() -> Void)? { get set }
        func start()
        func stop()
    }

    class NetworkMonitor: NetworkMonitoring {
        private let monitor = NWPathMonitor()
        private let monitorQueue = DispatchQueue(label: "com.topsort.analytics.NetworkMonitor")
        private let lock = NSLock()
        private var _isConnected = true
        var onConnectivityRestored: (() -> Void)?

        var isConnected: Bool {
            lock.withLock { _isConnected }
        }

        func start() {
            monitor.pathUpdateHandler = { [weak self] path in
                guard let self else { return }
                let wasConnected = self.lock.withLock { self._isConnected }
                let nowConnected = path.status == .satisfied
                self.lock.withLock { self._isConnected = nowConnected }
                if !wasConnected, nowConnected {
                    Logger.debug("Network connectivity restored — triggering flush")
                    self.onConnectivityRestored?()
                }
            }
            monitor.start(queue: monitorQueue)
        }

        func stop() {
            monitor.cancel()
        }
    }
#endif
