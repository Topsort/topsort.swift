import XCTest
@testable import Analytics

final class analytics_swiftTests: XCTestCase {
    func testExample() throws {
        // XCTest Documenation
        // https://developer.apple.com/documentation/xctest

        // Defining Test Cases and Test Methods
        // https://developer.apple.com/documentation/xctest/defining_test_cases_and_test_methods
    }
    
    func testEncodeModels() throws {
        let myEvent = Event(entity: Entity(type: EntityType.product, id: "product-id"), ocurredAt: Date.now, opaqueUserId: "user-id")
        let jsonEncoder = JSONEncoder()
        let jsonDecoder = JSONDecoder()
        jsonEncoder.dateEncodingStrategy = .iso8601
        jsonDecoder.dateDecodingStrategy = .iso8601
        
        let jsonData = try! jsonEncoder.encode(myEvent)
        let decoded = try! JSONSerialization.jsonObject(with: jsonData, options: []) as! [String: Any]
        
        assert(decoded["opaqueUserId"] as! String == "user-id")
        assert((decoded["entity"] as! [String: Any])["type"] as! String == "product")
    }
}
