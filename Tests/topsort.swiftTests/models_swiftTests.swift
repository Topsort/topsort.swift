import Foundation
@testable import Topsort
import XCTest

class EventModelTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Topsort.shared.set(opaqueUserId: "test-user")
    }

    // MARK: - Event encoding

    func testEventWithEntityEncoding() throws {
        let event = Event(entity: Entity(type: .product, id: "p1"), occurredAt: Date.now)
        let data = try JSONEncoder().encode(event)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["opaqueUserId"] as? String, "test-user")
        XCTAssertNotNil(json["entity"])
        XCTAssertNil(json["resolvedBidId"])
        XCTAssertNotNil(json["id"])
        XCTAssertNotNil(json["occurredAt"])
    }

    func testEventWithResolvedBidIdEncoding() throws {
        let event = Event(resolvedBidId: "bid-123", occurredAt: Date.now)
        let data = try JSONEncoder().encode(event)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["resolvedBidId"] as? String, "bid-123")
        XCTAssertNil(json["entity"])
    }

    func testEventWithExplicitOpaqueUserId() throws {
        let event = Event(entity: Entity(type: .vendor, id: "v1"), occurredAt: Date.now, opaqueUserId: "custom-user")
        let data = try JSONEncoder().encode(event)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["opaqueUserId"] as? String, "custom-user")
    }

    func testEventWithPlacement() throws {
        let placement = Placement(path: "/home", position: 3, page: 1, pageSize: 20, productId: "p1", categoryIds: ["c1", "c2"], searchQuery: "shoes")
        let event = Event(entity: Entity(type: .product, id: "p1"), occurredAt: Date.now, placement: placement)
        let data = try JSONEncoder().encode(event)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        let placementJson = try XCTUnwrap(json["placement"] as? [String: Any])
        XCTAssertEqual(placementJson["path"] as? String, "/home")
        XCTAssertEqual(placementJson["position"] as? Int, 3)
        XCTAssertEqual(placementJson["page"] as? Int, 1)
        XCTAssertEqual(placementJson["pageSize"] as? Int, 20)
        XCTAssertEqual(placementJson["productId"] as? String, "p1")
        XCTAssertEqual(placementJson["searchQuery"] as? String, "shoes")
    }

    func testEventIdIsUniquePerInstance() {
        let e1 = Event(entity: Entity(type: .product, id: "p1"), occurredAt: Date.now)
        let e2 = Event(entity: Entity(type: .product, id: "p1"), occurredAt: Date.now)
        XCTAssertNotEqual(e1.id, e2.id)
    }

    // MARK: - PurchaseEvent encoding

    func testPurchaseEventEncoding() throws {
        let item1 = PurchaseItem(productId: "p1", unitPrice: 9.99, quantity: 2)
        let item2 = PurchaseItem(productId: "p2", unitPrice: 14.50)
        let event = PurchaseEvent(items: [item1, item2], occurredAt: Date.now)

        let data = try JSONEncoder().encode(event)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["opaqueUserId"] as? String, "test-user")
        let items = try XCTUnwrap(json["items"] as? [[String: Any]])
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0]["productId"] as? String, "p1")
        XCTAssertEqual(items[0]["unitPrice"] as? Double, 9.99)
        XCTAssertEqual(items[0]["quantity"] as? Int, 2)
        XCTAssertEqual(items[1]["productId"] as? String, "p2")
        XCTAssertNil(items[1]["quantity"])
    }

    func testPurchaseEventWithExplicitOpaqueUserId() throws {
        let event = PurchaseEvent(items: [PurchaseItem(productId: "p1", unitPrice: 5.0)], occurredAt: Date.now, opaqueUserId: "injected-user")
        let data = try JSONEncoder().encode(event)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["opaqueUserId"] as? String, "injected-user")
    }

    // MARK: - Entity encoding

    func testEntityProductEncoding() throws {
        let entity = Entity(type: .product, id: "abc")
        let data = try JSONEncoder().encode(entity)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["type"] as? String, "product")
        XCTAssertEqual(json["id"] as? String, "abc")
    }

    func testEntityVendorEncoding() throws {
        let entity = Entity(type: .vendor, id: "v1")
        let data = try JSONEncoder().encode(entity)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["type"] as? String, "vendor")
    }

    // MARK: - Auction model encoding

    func testAuctionEncoding() throws {
        let products = try AuctionProducts(ids: ["p1", "p2"])
        let category = AuctionCategory(id: "c1")
        let geo = AuctionGeoTargeting(location: "US")
        let auction = Auction(type: "banners", slots: 1, slotId: "home", device: .mobile, products: products, category: category, searchQuery: "test", geoTargeting: geo)

        let data = try JSONEncoder().encode(auction)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["type"] as? String, "banners")
        XCTAssertEqual(json["slots"] as? Int, 1)
        XCTAssertEqual(json["slotId"] as? String, "home")
        XCTAssertEqual(json["device"] as? String, "mobile")
        XCTAssertEqual(json["searchQuery"] as? String, "test")
        XCTAssertNotNil(json["products"])
        XCTAssertNotNil(json["category"])
        XCTAssertNotNil(json["geoTargeting"])
    }

    func testAuctionMinimalEncoding() throws {
        let auction = Auction(type: "listings", slots: 3)
        let data = try JSONEncoder().encode(auction)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["type"] as? String, "listings")
        XCTAssertEqual(json["slots"] as? Int, 3)
        XCTAssertNil(json["slotId"])
        XCTAssertNil(json["device"])
    }

    func testAuctionCategoryWithIds() throws {
        let category = AuctionCategory(ids: ["c1", "c2"], disjunctions: [["d1", "d2"], ["d3"]])
        let data = try JSONEncoder().encode(category)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual((json["ids"] as? [String])?.count, 2)
        let disjunctions = try XCTUnwrap(json["disjunctions"] as? [[String]])
        XCTAssertEqual(disjunctions.count, 2)
        XCTAssertEqual(disjunctions[0], ["d1", "d2"])
        XCTAssertEqual(disjunctions[1], ["d3"])
    }

    func testAuctionResponseDecoding() throws {
        let responseJSON = """
        {
            "results": [
                {
                    "resultType": "banners",
                    "winners": [
                        {
                            "rank": 1,
                            "asset": [{"url": "https://cdn.example.com/banner.jpg"}],
                            "type": "product",
                            "id": "p1",
                            "resolvedBidId": "bid-abc"
                        }
                    ],
                    "error": false
                }
            ]
        }
        """
        let data = try XCTUnwrap(responseJSON.data(using: .utf8))
        let response = try JSONDecoder().decode(AuctionResponse.self, from: data)

        XCTAssertEqual(response.results.count, 1)
        XCTAssertEqual(response.results[0].resultType, "banners")
        XCTAssertEqual(response.results[0].winners.count, 1)
        XCTAssertEqual(response.results[0].winners[0].resolvedBidId, "bid-abc")
        XCTAssertEqual(response.results[0].winners[0].asset?.first?.url, "https://cdn.example.com/banner.jpg")
        XCTAssertFalse(response.results[0].error)
    }

    func testAuctionResponseWithNoWinners() throws {
        let responseJSON = """
        {
            "results": [
                {
                    "resultType": "listings",
                    "winners": [],
                    "error": false
                }
            ]
        }
        """
        let data = try XCTUnwrap(responseJSON.data(using: .utf8))
        let response = try JSONDecoder().decode(AuctionResponse.self, from: data)

        XCTAssertTrue(response.results[0].winners.isEmpty)
    }

    // MARK: - Events batch structure

    func testEventsBatchEncoding() throws {
        let impression = Event(entity: Entity(type: .product, id: "p1"), occurredAt: Date.now)
        let click = Event(entity: Entity(type: .product, id: "p2"), occurredAt: Date.now)
        let purchase = PurchaseEvent(items: [PurchaseItem(productId: "p3", unitPrice: 5.0)], occurredAt: Date.now)

        let events = Events(impressions: [impression], clicks: [click], purchases: [purchase])
        let data = try JSONEncoder().encode(events)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual((json["impressions"] as? [Any])?.count, 1)
        XCTAssertEqual((json["clicks"] as? [Any])?.count, 1)
        XCTAssertEqual((json["purchases"] as? [Any])?.count, 1)
    }

    // MARK: - TSDateValue

    func testDateEncodesAsISO8601WithFractionalSeconds() throws {
        let event = Event(entity: Entity(type: .product, id: "p1"), occurredAt: Date.now)
        let data = try JSONEncoder().encode(event)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let dateString = try XCTUnwrap(json["occurredAt"] as? String)

        // Should contain T separator and fractional seconds
        XCTAssertTrue(dateString.contains("T"))
        XCTAssertTrue(dateString.contains("."))
    }

    func testTSDateValueDecodeFromISO8601() throws {
        let json = """
        {"occurredAt": "2025-01-15T10:30:00.123Z", "opaqueUserId": "u1", "id": "00000000-0000-0000-0000-000000000001", "items": [{"productId": "p1", "unitPrice": 5.0}]}
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let event = try JSONDecoder().decode(PurchaseEvent.self, from: data)
        // Verify it decoded without throwing
        XCTAssertEqual(event.opaqueUserId, "u1")
    }

    func testTSDateValueDecodeInvalidDateThrows() throws {
        let json = """
        {"occurredAt": "not-a-date", "opaqueUserId": "u1", "id": "00000000-0000-0000-0000-000000000001", "items": [{"productId": "p1", "unitPrice": 5.0}]}
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        XCTAssertThrowsError(try JSONDecoder().decode(PurchaseEvent.self, from: data))
    }

    func testTSDateValueRoundTrip() throws {
        let original = PurchaseEvent(items: [PurchaseItem(productId: "p1", unitPrice: 5.0)], occurredAt: Date.now)
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PurchaseEvent.self, from: encoded)
        // Dates should be within 1ms (fractional seconds precision)
        XCTAssertEqual(decoded.occurredAt.timeIntervalSince1970, original.occurredAt.timeIntervalSince1970, accuracy: 0.001)
    }

    // MARK: - Events init variants

    func testEventsInitWithClicksFirst() throws {
        let click = Event(entity: Entity(type: .product, id: "p1"), occurredAt: Date.now)
        let events = Events(clicks: [click])
        let data = try JSONEncoder().encode(events)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual((json["clicks"] as? [Any])?.count, 1)
    }

    func testEventsInitWithPurchasesFirst() throws {
        let purchase = PurchaseEvent(items: [PurchaseItem(productId: "p1", unitPrice: 5.0)], occurredAt: Date.now)
        let events = Events(purchases: [purchase])
        let data = try JSONEncoder().encode(events)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual((json["purchases"] as? [Any])?.count, 1)
    }

    func testPlacementMinimalInit() throws {
        let placement = Placement(path: "/home")
        let data = try JSONEncoder().encode(placement)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["path"] as? String, "/home")
        XCTAssertNil(json["position"])
        XCTAssertNil(json["page"])
    }

    // MARK: - Spec enums

    /// The raw values are what goes on the wire; they must be the API's enum values exactly.
    func testSpecEnumRawValuesMatchTheAPI() {
        XCTAssertEqual([DeviceType.desktop, .mobile].map(\.rawValue), ["desktop", "mobile"])
        XCTAssertEqual([Channel.onsite, .offsite, .instore].map(\.rawValue), ["onsite", "offsite", "instore"])
        XCTAssertEqual([ClickType.product, .like, .addToCart].map(\.rawValue), ["product", "like", "add-to-cart"])
        XCTAssertEqual(
            [PageType.home, .category, .pdp, .search, .cart, .other].map(\.rawValue),
            ["home", "category", "PDP", "search", "cart", "other"]
        )
    }

    // MARK: - Spec rules the types cannot express

    func testPlacementSpecViolations() {
        XCTAssertNil(Placement(path: "/home", position: 1, page: 1, pageSize: 1, productId: "p", categoryIds: ["c"], searchQuery: "q").specViolation)
        XCTAssertNotNil(Placement(path: "").specViolation)
        XCTAssertNotNil(Placement(path: "/home", position: 0).specViolation)
        XCTAssertNotNil(Placement(path: "/home", page: 0).specViolation)
        XCTAssertNotNil(Placement(path: "/home", pageSize: 0).specViolation)
        XCTAssertNotNil(Placement(path: "/home", productId: "").specViolation)
        XCTAssertNotNil(Placement(path: "/home", categoryIds: []).specViolation)
        XCTAssertNotNil(Placement(path: "/home", searchQuery: "").specViolation)
    }

    func testEventSpecViolations() {
        XCTAssertNil(Event(resolvedBidId: "bid", occurredAt: Date.now, opaqueUserId: "u").specViolation)
        XCTAssertNotNil(Event(resolvedBidId: "bid", occurredAt: Date.now, opaqueUserId: "u", id: "").specViolation)
        XCTAssertNotNil(RenderEvent(resolvedBidId: "bid", occurredAt: Date.now, opaqueUserId: "u", placement: Placement(path: "")).specViolation)
        XCTAssertNotNil(VideoEvent(resolvedBidId: "bid", checkpoint: .start, occurredAt: Date.now, opaqueUserId: "u", id: "").specViolation)
        XCTAssertNotNil(PurchaseEvent(items: [PurchaseItem(productId: "p", unitPrice: 1)], occurredAt: Date.now, opaqueUserId: "u", id: "").specViolation)
        XCTAssertNotNil(PageViewEvent(page: Page(type: .cart, pageId: "cart", values: []), occurredAt: Date.now, opaqueUserId: "u").specViolation)
    }

    // MARK: - Persisted queue

    /// A queue saved by an earlier version can hold a value the current models reject (a free-form
    /// deviceType, say). That event is skipped; the rest of the file must still load.
    func testPersistedQueueSkipsEventsThatNoLongerDecode() throws {
        let items: [EventItem] = (0 ..< 3).map { .click(Event(resolvedBidId: "bid-\($0)", occurredAt: Date.now, opaqueUserId: "u")) }
        let plist = try PropertyListEncoder().encode(PersistedValueWrapper(value: items))
        var root = try XCTUnwrap(PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any])
        var stored = try XCTUnwrap(root["value"] as? [[String: Any]])
        var click = try XCTUnwrap(stored[1]["click"] as? [String: Any])
        var event = try XCTUnwrap(click["_0"] as? [String: Any])
        event["deviceType"] = "tablet"
        click["_0"] = event
        stored[1]["click"] = click
        root["value"] = stored
        let legacy = try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)

        XCTAssertThrowsError(try PropertyListDecoder().decode(PersistedValueWrapper<[EventItem]>.self, from: legacy), "a plain array loses the whole file")
        let queue = try PropertyListDecoder().decode(PersistedValueWrapper<LossyArray<EventItem>>.self, from: legacy).value.elements
        XCTAssertEqual(queue.count, 2)
    }

    /// LossyArray must write the same shape as a plain array, so files stay readable both ways.
    func testLossyArrayEncodesLikeAPlainArray() throws {
        let items: [EventItem] = [.click(Event(resolvedBidId: "bid", occurredAt: Date(timeIntervalSince1970: 0), opaqueUserId: "u", id: "e1"))]
        XCTAssertEqual(try JSONEncoder().encode(LossyArray(items)), try JSONEncoder().encode(items))
    }
}
