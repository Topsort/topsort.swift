import Foundation

#if canImport(UIKit) && !os(watchOS)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

class LifecycleObserver {
    private let onBackground: () -> Void
    private let onTerminate: () -> Void
    private var observers: [Any] = []

    init(onBackground: @escaping () -> Void, onTerminate: @escaping () -> Void) {
        self.onBackground = onBackground
        self.onTerminate = onTerminate
        registerNotifications()
    }

    private func registerNotifications() {
        #if canImport(UIKit) && !os(watchOS)
            observers.append(
                NotificationCenter.default.addObserver(
                    forName: UIApplication.didEnterBackgroundNotification,
                    object: nil, queue: .main
                ) { [weak self] _ in self?.onBackground() }
            )
            observers.append(
                NotificationCenter.default.addObserver(
                    forName: UIApplication.willTerminateNotification,
                    object: nil, queue: .main
                ) { [weak self] _ in self?.onTerminate() }
            )
        #elseif canImport(AppKit)
            observers.append(
                NotificationCenter.default.addObserver(
                    forName: NSApplication.willResignActiveNotification,
                    object: nil, queue: .main
                ) { [weak self] _ in self?.onBackground() }
            )
            observers.append(
                NotificationCenter.default.addObserver(
                    forName: NSApplication.willTerminateNotification,
                    object: nil, queue: .main
                ) { [weak self] _ in self?.onTerminate() }
            )
        #endif
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
