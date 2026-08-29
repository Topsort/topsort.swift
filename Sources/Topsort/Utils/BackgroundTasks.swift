#if canImport(UIKit) && !os(watchOS)
    import UIKit

    protocol BackgroundTaskProviding {
        func begin(name: String, expiration: @escaping () -> Void) -> UIBackgroundTaskIdentifier
        func end(_ task: UIBackgroundTaskIdentifier)
    }

    /// `UIApplication.shared` is unavailable to app extensions, so the application is reached
    /// through the selector. Where there is none — an extension, or a test bundle with no host
    /// app — there is nothing to hold and `begin` reports `.invalid`.
    struct UIApplicationBackgroundTasks: BackgroundTaskProviding {
        private var application: UIApplication? {
            guard !Bundle.main.bundlePath.hasSuffix(".appex") else { return nil }
            return UIApplication.perform(NSSelectorFromString("sharedApplication"))?.takeUnretainedValue() as? UIApplication
        }

        func begin(name: String, expiration: @escaping () -> Void) -> UIBackgroundTaskIdentifier {
            application?.beginBackgroundTask(withName: name, expirationHandler: expiration) ?? .invalid
        }

        func end(_ task: UIBackgroundTaskIdentifier) {
            application?.endBackgroundTask(task)
        }
    }
#endif
