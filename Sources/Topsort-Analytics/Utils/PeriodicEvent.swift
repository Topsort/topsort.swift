import Foundation

class PeriodicEvent {
    private let queue: DispatchQueue
    private static let serialQueue = DispatchQueue(label: "com.topsort.analytics.PeriodicEvent")
    private let interval: TimeInterval
    private var workItem: DispatchWorkItem?
    private let action: () -> Void
    private var isRunning = false
    init(interval: TimeInterval, action: @escaping (() -> Void), queue: DispatchQueue = .main) {
        self.interval = interval
        self.queue = queue
        self.action = action
    }
    func start() {
        Self.serialQueue.async {
            self.isRunning = true
            self.runNext()
        }
    }
    func stop() {
        Self.serialQueue.async {
            self.isRunning = false
            self.workItem?.cancel()
        }
    }
    private func runNext() {
        Self.serialQueue.async {
            guard self.isRunning else { return }
            self.workItem?.cancel()
            let workItem = DispatchWorkItem(block: self.process)
            self.workItem = workItem
            self.queue.asyncAfter(deadline: .now() + self.interval, execute: workItem)
        }
    }
    private func process() {
        self.action()
        self.runNext()
    }
}
