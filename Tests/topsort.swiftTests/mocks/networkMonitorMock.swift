#if canImport(Network)
    @testable import Topsort

    class MockNetworkMonitor: NetworkMonitoring {
        var isConnected: Bool = true
        var onConnectivityRestored: (() -> Void)?
        var startCalled = false
        var stopCalled = false

        func start() {
            startCalled = true
        }

        func stop() {
            stopCalled = true
        }

        func simulateReconnect() {
            isConnected = true
            onConnectivityRestored?()
        }
    }
#endif
