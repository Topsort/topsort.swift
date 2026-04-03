#if canImport(Network)
    import Foundation
    @testable import Topsort
    import XCTest

    class NetworkReachabilityTests: XCTestCase {
        var eventManager: EventManager!
        var mockClient: MockHTTPClient!
        var mockNetwork: MockNetworkMonitor!

        override func setUp() {
            super.setUp()
            mockClient = MockHTTPClient(apiKey: nil, postResult: .success(Data()))
            mockNetwork = MockNetworkMonitor()
            eventManager = EventManager.shared
            eventManager.client = mockClient
            eventManager.networkMonitor = mockNetwork
            eventManager._eventQueue = []
            eventManager._pendingEvents = [:]
            eventManager.flushAt = 1
            Topsort.shared.set(opaqueUserId: "test-user")
        }

        override func tearDown() {
            eventManager = nil
            mockClient = nil
            mockNetwork = nil
            super.tearDown()
        }

        func testSendSkippedWhenOffline() {
            mockNetwork.isConnected = false

            let event = Event(entity: Entity(type: .product, id: "p1"), occurredAt: Date.now)
            eventManager.push(event: .impression(event))

            // Wait briefly
            let exp = expectation(description: "wait")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exp.fulfill() }
            wait(for: [exp], timeout: 2)

            XCTAssertFalse(mockClient.postCalled, "Should not send when offline")
        }

        func testSendProceedsWhenOnline() {
            mockNetwork.isConnected = true

            let event = Event(entity: Entity(type: .product, id: "p1"), occurredAt: Date.now)
            eventManager.push(event: .impression(event))

            let predicate = NSPredicate { _, _ in self.mockClient.postCalled }
            let exp = expectation(for: predicate, evaluatedWith: nil)
            wait(for: [exp], timeout: 3)

            XCTAssertTrue(mockClient.postCalled)
        }

        func testManualFlushSendsWhenOnline() {
            // Verify that flush() works when online, using the mock network monitor
            eventManager.flushAt = 100 // High threshold
            mockNetwork.isConnected = true

            let event = Event(entity: Entity(type: .product, id: "p1"), occurredAt: Date.now)
            eventManager.push(event: .impression(event))

            // Wait for push to enqueue
            let waitExp = expectation(description: "wait")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { waitExp.fulfill() }
            wait(for: [waitExp], timeout: 1)

            XCTAssertFalse(mockClient.postCalled, "Below threshold, should not auto-send")

            // Manual flush
            eventManager.flush()

            let predicate = NSPredicate { _, _ in self.mockClient.postCalled }
            let exp = expectation(for: predicate, evaluatedWith: nil)
            wait(for: [exp], timeout: 3)

            XCTAssertTrue(mockClient.postCalled)
        }
    }
#endif
