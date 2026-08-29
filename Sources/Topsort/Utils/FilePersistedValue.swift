import Foundation

struct PersistedValueWrapper<T: Codable>: Codable {
    let value: T
}

@propertyWrapper
public class FilePersistedValue<T: Codable> {
    private let serialQueue = DispatchQueue(label: "com.topsort.analytics.FilePersistedValue")
    private let storePath: String
    private var value: T?
    private var isDirty = false
    private var debouncedPersistWorkItem: DispatchWorkItem?
    var deferPersistence: Bool = false
    var debounceInterval: TimeInterval = 5.0

    public init(storePath: String) {
        self.storePath = storePath
        let url = URL(fileURLWithPath: self.storePath)
        do {
            let data = try? Data(contentsOf: url)
            let value = try data.map { data in try PropertyListDecoder().decode(PersistedValueWrapper<T>.self, from: data).value }
            self.value = value
        } catch {
            Logger.error("Error loading persisted value: \(error)")
        }
    }

    public var wrappedValue: T? {
        get { serialQueue.sync { value } }
        set {
            serialQueue.sync { value = newValue }
            if deferPersistence {
                serialQueue.async { self.scheduleDebouncedPersist() }
            } else {
                persist(value: newValue)
            }
        }
    }

    func persistIfDirty() {
        serialQueue.sync {
            guard self.isDirty else { return }
            self.debouncedPersistWorkItem?.cancel()
            self.isDirty = false
            self.persistSync(value: self.value)
        }
    }

    private func scheduleDebouncedPersist() {
        isDirty = true
        debouncedPersistWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.isDirty else { return }
            self.isDirty = false
            self.persistSync(value: self.value)
        }
        debouncedPersistWorkItem = workItem
        serialQueue.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }

    private func persist(value: T?) {
        serialQueue.async {
            self.persistSync(value: value)
        }
    }

    private func persistSync(value: T?) {
        do {
            let url = URL(fileURLWithPath: storePath)
            guard let value else {
                if FileManager.default.fileExists(atPath: storePath) {
                    try FileManager.default.removeItem(atPath: storePath)
                }
                return
            }
            let data = try PropertyListEncoder().encode(PersistedValueWrapper(value: value))
            // Atomic: a crash mid-write must leave the previous file, not no file.
            try data.write(to: url, options: .atomic)
        } catch {
            Logger.error("Error persisting value: \(error)")
        }
    }
}
