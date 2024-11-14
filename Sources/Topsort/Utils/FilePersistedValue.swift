import Foundation

struct PersistedValueWrapper<T: Codable>: Codable {
    let value: T
}

@propertyWrapper
public class FilePersistedValue<T: Codable> {
    private let serialQueue = DispatchQueue(label: "com.topsort.analytics.FilePersistedValue")
    private let storePath: String
    private var value: T?

    public init(storePath: String) {
        self.storePath = storePath
        let url = URL(fileURLWithPath: self.storePath)
        do {
            let data = try? Data(contentsOf: url)
            let value = try data.map { data in try PropertyListDecoder().decode(PersistedValueWrapper<T>.self, from: data).value }
            self.value = value
        } catch {
            print("Error loading persisted value: \(error)")
        }
    }

    public var wrappedValue: T? {
        get { value }
        set {
            value = newValue
            persist(value: newValue)
        }
    }

    private func persist(value: T?) {
        serialQueue.async {
            do {
                let fileManager = FileManager.default
                if fileManager.fileExists(atPath: self.storePath) {
                    try fileManager.removeItem(atPath: self.storePath)
                }
                guard value != nil else { return }
                let data = try PropertyListEncoder().encode(PersistedValueWrapper(value: value))
                let url = URL(fileURLWithPath: self.storePath)
                try data.write(to: url)
            } catch {
                print("Error persisting value: \(error)")
            }
        }
    }
}
