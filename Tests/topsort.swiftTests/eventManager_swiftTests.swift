import Foundation
@testable import Topsort
import XCTest



class EventSender {
    private let queue = DispatchQueue(label: "com.topsort.EventSender", qos: .background)
    private let event: Event
    @FilePersistedValue(storePath: PathHelper.path(for: "com.topsort.analytics.event-queue-test.plist"))
    private var _eventQueue: [EventItem]?
    private var eventQueue: [EventItem] {
        get {
            if let eq = _eventQueue {
                return eq
            } else {
                _eventQueue = []
                return []
            }
        }
        set {
            _eventQueue = newValue
        }
    }
    
    init() {
        self.event = Event(
            entity: Entity(type: EntityType.product, id: "xpto"), 
            occurredAt: Date.now
        )
    }
    
    func start() {
        queue.async { 
            self.sendEvents()
        }
    }
    
    private func sendEvents() {
        while true {
            if Int.random(in: 0...2) == 0 {
                eventQueue = []
            } else {
                eventQueue.append(.click(event))
            }
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
        let sender: EventSender? = EventSender()
        sender?.start()
        try? await Task.sleep(nanoseconds: 1_000_000_000)
    }
}
