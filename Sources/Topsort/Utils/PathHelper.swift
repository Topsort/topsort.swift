import Foundation

class PathHelper {
    private init() {}
    private static let storagePath: String = {
        let appSupport = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true)[0]
        let dir = "\(appSupport)/com.topsort.analytics"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func path(for file: String) -> String {
        return "\(storagePath)/\(file)"
    }
}
