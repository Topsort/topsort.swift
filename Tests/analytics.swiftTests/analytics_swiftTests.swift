import XCTest
@testable import Topsort_Analytics

final class analytics_swiftTests: XCTestCase {
    func testExample() throws {
        // XCTest Documenation
        // https://developer.apple.com/documentation/xctest

        // Defining Test Cases and Test Methods
        // https://developer.apple.com/documentation/xctest/defining_test_cases_and_test_methods
    }
    
    func testEncodeModels() throws {
        let date = Date()
        let iso8601DateFormatter = ISO8601DateFormatter()
        iso8601DateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let occurredAt = iso8601DateFormatter.string(from: date)

        let myEvent = Event(entity: Entity(type: EntityType.product, id: "product-id"), occurredAt: occurredAt, opaqueUserId: "user-id")
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
