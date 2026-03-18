import Foundation

class PathHelper {
    private init() {}
    private static let documentsPath: String = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]

    static func path(for file: String) -> String {
        return "\(documentsPath)/\(file)"
    }
}
