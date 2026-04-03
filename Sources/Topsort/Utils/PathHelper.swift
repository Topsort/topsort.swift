import Foundation

class PathHelper {
    private init() {}
    private static let legacyPath: String = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
    private static let storagePath: String = {
        let appSupport = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true)[0]
        let dir = "\(appSupport)/com.topsort.analytics"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        migrateFromDocuments(to: dir)
        return dir
    }()

    static func path(for file: String) -> String {
        return "\(storagePath)/\(file)"
    }

    private static func migrateFromDocuments(to newDir: String) {
        let fileManager = FileManager.default
        let files = [
            "com.topsort.analytics.opaque-user-id.plist",
            "com.topsort.analytics.event-queue.plist",
            "com.topsort.analytics.pending-events.plist",
        ]
        for file in files {
            let oldPath = "\(legacyPath)/\(file)"
            let newPath = "\(newDir)/\(file)"
            guard fileManager.fileExists(atPath: oldPath),
                  !fileManager.fileExists(atPath: newPath)
            else { continue }
            do {
                try fileManager.moveItem(atPath: oldPath, toPath: newPath)
            } catch {
                Logger.error("Failed to migrate \(file): \(error)")
            }
        }
    }
}
