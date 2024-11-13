import Foundation
@testable import Topsort
import XCTest

class EventSender {
    private var isRunning = false
    private let queue = DispatchQueue(label: "com.topsort.EventSender", qos: .background)
    private let event: Event
    private let intervalSeconds: Double
    
    init(intervalSeconds: Double = 0.1) {
        // Create a sample event
        self.event = Event(
            entity: Entity(type: EntityType.product, id: "xpto"), 
            occurredAt: Date.now
        )
        self.intervalSeconds = intervalSeconds
    }

    deinit{
        print(">>>>>>>>>>> eventSender deinit")
    }
    
    func start() {
        isRunning = true
        queue.async { 
            self.sendEvents()
        }
    }
    
    func stop() {
        isRunning = false
    }
    
    private func sendEvents() {
        while isRunning {
            EventManager.shared.push(event: .click(event))
            //print("EventSender: Pushed click event")
            
            // Sleep for a short interval to prevent overwhelming the system
            //Thread.sleep(forTimeInterval: intervalSeconds)
        }
    }
}

class EventManagerTests: XCTestCase {
    var mockClient: MockHTTPClient!

    override func setUp() {
        super.setUp()
        mockClient = MockHTTPClient(apiKey: nil, postResult: .success(Data()))
        EventManager.shared.client = mockClient
    }

    override func tearDown() {
        //eventManager = nil
        mockClient = nil
        super.tearDown()
    }

    func testConfigure() {
        let apiKey = "testApiKey"
        let urlString = "https://test.com"
        EventManager.shared.configure(apiKey: apiKey, url: urlString)

        XCTAssertEqual(mockClient.apiKey, apiKey)
        XCTAssertEqual(EventManager.shared.url.absoluteString, "\(urlString)/events")
    }
    
    func testExecuteEvents() async {
        var sender: EventSender? = EventSender(intervalSeconds: 0.01)
        sender?.start()
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        //sender?.stop()
        sender = nil   // This will trigger deinit
        print("stopped")
        try? await Task.sleep(nanoseconds: 5_000_000_000)
    }
}
