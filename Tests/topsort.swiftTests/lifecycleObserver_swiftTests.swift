@testable import Topsort
import XCTest

#if canImport(AppKit)
    import AppKit
#endif

class LifecycleObserverTests: XCTestCase {
    #if canImport(AppKit)
        func testOnBackgroundCalledOnResignActive() {
            let exp = expectation(description: "onBackground called")
            let observer = LifecycleObserver(
                onBackground: { exp.fulfill() },
                onTerminate: {}
            )

            // Post on main queue run loop
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: NSApplication.willResignActiveNotification,
                    object: nil
                )
            }

            wait(for: [exp], timeout: 2)
            _ = observer // keep alive
        }

        func testOnTerminateCalledOnWillTerminate() {
            let exp = expectation(description: "onTerminate called")
            let observer = LifecycleObserver(
                onBackground: {},
                onTerminate: { exp.fulfill() }
            )

            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: NSApplication.willTerminateNotification,
                    object: nil
                )
            }

            wait(for: [exp], timeout: 2)
            _ = observer
        }
    #endif
}
