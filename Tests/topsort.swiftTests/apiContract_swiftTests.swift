import Foundation
@testable import Topsort
import XCTest

/// Tests that verify SDK models produce JSON matching the Topsort API contract.
/// Based on the OpenAPI spec at /v2/auctions and /v2/events.
class APIContractAuctionTests: XCTestCase {
    // MARK: - Auction request encoding

    func testListingsAuctionMatchesAPIFormat() throws {
        let products = try AuctionProducts(ids: ["p_PJbnN", "p_ojng4"])
        let auction = Auction(type: "listings", slots: 2, device: .mobile, products: products)

        let payload = ["auctions": [auction]]
        let data = try JSONEncoder().encode(payload)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let auctions = try XCTUnwrap(json["auctions"] as? [[String: Any]])

        XCTAssertEqual(auctions.count, 1)
        XCTAssertEqual(auctions[0]["type"] as? String, "listings")
        XCTAssertEqual(auctions[0]["slots"] as? Int, 2)
        XCTAssertEqual(auctions[0]["device"] as? String, "mobile")
    }

    func testBannerAuctionMatchesAPIFormat() throws {
        let category = AuctionCategory(id: "shoes")
        let auction = Auction(type: "banners", slots: 1, slotId: "home-banner", device: .desktop, category: category)

        let data = try JSONEncoder().encode(auction)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["type"] as? String, "banners")
        XCTAssertEqual(json["slotId"] as? String, "home-banner")
        XCTAssertNotNil(json["category"])
    }

    func testAuctionWithNewFieldsMatchesAPIFormat() throws {
        let auction = Auction(
            type: "listings",
            slots: 3,
            opaqueUserId: "user-123",
            placementId: 42
        )

        let data = try JSONEncoder().encode(auction)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["opaqueUserId"] as? String, "user-123")
        XCTAssertEqual(json["placementId"] as? Int, 42)
    }

    func testCategoryDisjunctionsMatchesAPIFormat() throws {
        let category = AuctionCategory(disjunctions: [["shoes", "sneakers"], ["running"]])
        let data = try JSONEncoder().encode(category)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let disjunctions = try XCTUnwrap(json["disjunctions"] as? [[String]])

        XCTAssertEqual(disjunctions.count, 2)
        XCTAssertEqual(disjunctions[0], ["shoes", "sneakers"])
    }

    func testNilFieldsOmittedInJSON() throws {
        let auction = Auction(type: "listings", slots: 1)
        let data = try JSONEncoder().encode(auction)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        // Optional fields should not be present when nil
        XCTAssertNil(json["slotId"])
        XCTAssertNil(json["device"])
        XCTAssertNil(json["products"])
        XCTAssertNil(json["category"])
        XCTAssertNil(json["opaqueUserId"])
        XCTAssertNil(json["placementId"])
    }

    // MARK: - Auction response decoding

    func testDecodeResponseWithCampaignId() throws {
        let json = """
        {
            "results": [{
                "resultType": "listings",
                "winners": [{
                    "rank": 1,
                    "type": "product",
                    "id": "p_Mfk11",
                    "resolvedBidId": "abc123",
                    "campaignId": "82588593-85c5-47c0-b125-07e315b7f2b3"
                }],
                "error": false
            }]
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let response = try JSONDecoder().decode(AuctionResponse.self, from: data)
        let winner = try XCTUnwrap(response.results.first?.winners.first)

        XCTAssertEqual(winner.campaignId, "82588593-85c5-47c0-b125-07e315b7f2b3")
        XCTAssertEqual(winner.type, "product")
        XCTAssertEqual(winner.resolvedBidId, "abc123")
    }

    func testDecodeResponseWithAssetContent() throws {
        let json = """
        {
            "results": [{
                "resultType": "banners",
                "winners": [{
                    "rank": 1,
                    "type": "product",
                    "id": "p_PJbnN",
                    "resolvedBidId": "xyz",
                    "asset": [{
                        "url": "https://cdn.example.com/banner.png",
                        "content": {
                            "headingText": "Shop Now",
                            "bannerText": "Best deals"
                        }
                    }]
                }],
                "error": false
            }]
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let response = try JSONDecoder().decode(AuctionResponse.self, from: data)
        let asset = try XCTUnwrap(response.results.first?.winners.first?.asset?.first)

        XCTAssertEqual(asset.url, "https://cdn.example.com/banner.png")
        XCTAssertEqual(asset.content?["headingText"], "Shop Now")
        XCTAssertEqual(asset.content?["bannerText"], "Best deals")
    }

    func testDecodeResponseWithoutCampaignId() throws {
        let json = """
        {
            "results": [{
                "resultType": "listings",
                "winners": [{
                    "rank": 1,
                    "type": "product",
                    "id": "p1",
                    "resolvedBidId": "abc"
                }],
                "error": false
            }]
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let response = try JSONDecoder().decode(AuctionResponse.self, from: data)
        let winner = try XCTUnwrap(response.results.first?.winners.first)

        XCTAssertNil(winner.campaignId)
    }
}

class APIContractEventTests: XCTestCase {
    /// `id` is the idempotency key the API dedups on. A host that has its own order or
    /// impression id passes it so a retry after a crash cannot double-count.
    func testHostSuppliedIdsAreSentVerbatim() throws {
        let id = "ORD-12345"
        func idField<T: Encodable>(_ value: T) throws -> String? {
            try (JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])?["id"] as? String
        }
        XCTAssertEqual(try idField(Event(entity: Entity(type: .product, id: "p1"), occurredAt: Date.now, id: id)), id)
        XCTAssertEqual(try idField(Event(resolvedBidId: "bid", occurredAt: Date.now, id: id)), id)
        XCTAssertEqual(try idField(PurchaseEvent(items: [PurchaseItem(productId: "p1", unitPrice: 1)], occurredAt: Date.now, id: id)), id)
        XCTAssertEqual(try idField(PageViewEvent(page: Page(type: .home, pageId: "home"), occurredAt: Date.now, id: id)), id)
        XCTAssertEqual(try idField(RenderEvent(resolvedBidId: "bid", occurredAt: Date.now, id: id)), id)
        XCTAssertEqual(try idField(VideoEvent(resolvedBidId: "bid", checkpoint: .start, occurredAt: Date.now, id: id)), id)
        XCTAssertNotNil(UUID(uuidString: Event(entity: Entity(type: .product, id: "p1"), occurredAt: Date.now).id), "the default must still mint a fresh UUID")
    }

    override func setUp() {
        super.setUp()
        Topsort.shared.set(opaqueUserId: "user-123")
    }

    // MARK: - Event encoding

    func testImpressionWithDeviceTypeAndChannel() throws {
        let event = Event(
            resolvedBidId: "bid-abc",
            occurredAt: Date.now,
            opaqueUserId: "user-123",
            deviceType: .mobile,
            channel: .onsite
        )

        let data = try JSONEncoder().encode(event)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["deviceType"] as? String, "mobile")
        XCTAssertEqual(json["channel"] as? String, "onsite")
        XCTAssertEqual(json["resolvedBidId"] as? String, "bid-abc")
    }

    func testClickWithClickType() throws {
        let event = Event(
            resolvedBidId: "bid-abc",
            occurredAt: Date.now,
            opaqueUserId: "user-123",
            clickType: .addToCart
        )

        let data = try JSONEncoder().encode(event)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["clickType"] as? String, "add-to-cart")
    }

    func testEventWithAdditionalAttribution() throws {
        let attr = Entity(type: .vendor, id: "vendor-1")
        let event = Event(
            resolvedBidId: "bid-abc",
            occurredAt: Date.now,
            opaqueUserId: "user-123",
            additionalAttribution: attr
        )

        let data = try JSONEncoder().encode(event)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let attribution = try XCTUnwrap(json["additionalAttribution"] as? [String: Any])

        XCTAssertEqual(attribution["type"] as? String, "vendor")
        XCTAssertEqual(attribution["id"] as? String, "vendor-1")
    }

    func testNewEventFieldsNilOmitted() throws {
        let event = Event(entity: Entity(type: .product, id: "p1"), occurredAt: Date.now)
        let data = try JSONEncoder().encode(event)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertNil(json["deviceType"])
        XCTAssertNil(json["channel"])
        XCTAssertNil(json["additionalAttribution"])
        XCTAssertNil(json["clickType"])
    }

    // MARK: - Purchase with new fields

    func testPurchaseWithVendorId() throws {
        let item = PurchaseItem(productId: "p1", unitPrice: 9.99, vendorId: "vendor-1")
        let purchase = PurchaseEvent(
            items: [item],
            occurredAt: Date.now,
            opaqueUserId: "user-123",
            deviceType: .desktop,
            channel: .offsite
        )

        let data = try JSONEncoder().encode(purchase)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["deviceType"] as? String, "desktop")
        XCTAssertEqual(json["channel"] as? String, "offsite")

        let items = try XCTUnwrap(json["items"] as? [[String: Any]])
        XCTAssertEqual(items[0]["vendorId"] as? String, "vendor-1")
    }

    // MARK: - PageView event

    func testPageViewEventEncoding() throws {
        let page = Page(type: .category, pageId: "cat-shoes", value: "Shoes")
        let pageview = PageViewEvent(
            page: page,
            occurredAt: Date.now,
            opaqueUserId: "user-123",
            deviceType: .mobile,
            channel: .onsite
        )

        let data = try JSONEncoder().encode(pageview)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["opaqueUserId"] as? String, "user-123")
        XCTAssertEqual(json["deviceType"] as? String, "mobile")
        XCTAssertNotNil(json["id"])
        XCTAssertNotNil(json["occurredAt"])

        let pageJson = try XCTUnwrap(json["page"] as? [String: Any])
        XCTAssertEqual(pageJson["type"] as? String, "category")
        XCTAssertEqual(pageJson["pageId"] as? String, "cat-shoes")
        XCTAssertEqual(pageJson["value"] as? String, "Shoes")
    }

    // MARK: - Events batch with pageviews

    func testEventsBatchIncludesPageviews() throws {
        let page = Page(type: .home, pageId: "home-1")
        let pageview = PageViewEvent(page: page, occurredAt: Date.now)
        let events = Events(pageviews: [pageview])

        let data = try JSONEncoder().encode(events)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual((json["pageviews"] as? [Any])?.count, 1)
    }

    // MARK: - EventItem grouping with pageviews

    func testEventItemGroupsPageviews() {
        Topsort.shared.set(opaqueUserId: "test-user")
        let page = Page(type: .search, pageId: "search-1", value: "shoes")
        let pageview = PageViewEvent(page: page, occurredAt: Date.now)
        let impression = Event(entity: Entity(type: .product, id: "p1"), occurredAt: Date.now)

        let items: [EventItem] = [
            .pageview(pageview),
            .impression(impression),
        ]

        let events = items.toEvents()

        XCTAssertEqual(events.pageviews?.count, 1)
        XCTAssertEqual(events.impressions?.count, 1)
    }

    // MARK: - Render event

    func testRenderEventEncoding() throws {
        let render = RenderEvent(
            resolvedBidId: "bid-abc",
            occurredAt: Date.now,
            opaqueUserId: "user-123",
            deviceType: .mobile,
            channel: .onsite
        )

        let data = try JSONEncoder().encode(render)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["resolvedBidId"] as? String, "bid-abc")
        XCTAssertEqual(json["opaqueUserId"] as? String, "user-123")
        XCTAssertEqual(json["deviceType"] as? String, "mobile")
        XCTAssertEqual(json["channel"] as? String, "onsite")
        XCTAssertNotNil(json["id"])
        XCTAssertNotNil(json["occurredAt"])
    }

    // MARK: - Events batch with renders

    func testEventsBatchIncludesRenders() throws {
        let render = RenderEvent(resolvedBidId: "bid-abc", occurredAt: Date.now)
        let events = Events(renders: [render])

        let data = try JSONEncoder().encode(events)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual((json["renders"] as? [Any])?.count, 1)
    }

    // MARK: - EventItem grouping with renders

    func testEventItemGroupsRenders() {
        Topsort.shared.set(opaqueUserId: "test-user")
        let render = RenderEvent(resolvedBidId: "bid-abc", occurredAt: Date.now)
        let impression = Event(entity: Entity(type: .product, id: "p1"), occurredAt: Date.now)

        let items: [EventItem] = [
            .render(render),
            .impression(impression),
        ]

        let events = items.toEvents()

        XCTAssertEqual(events.renders?.count, 1)
        XCTAssertEqual(events.impressions?.count, 1)
    }

    // MARK: - Video event

    /// The wire values must be exactly the VAST names the API's `eventType` enum accepts; anything
    /// else is a non-retriable 400 that takes the rest of the batch down with it.
    func testVideoCheckpointRawValuesMatchTheAPIEnum() {
        XCTAssertEqual(
            [VideoCheckpoint.start, .firstQuartile, .midpoint, .thirdQuartile, .complete].map(\.rawValue),
            ["start", "firstQuartile", "midpoint", "thirdQuartile", "complete"]
        )
    }

    /// Public types get no inferred Sendable, and an app in Swift 6 mode captures the checkpoint
    /// in a player callback; this fails to compile if the conformance is dropped.
    func testVideoCheckpointIsSendable() {
        func requireSendable<T: Sendable>(_: T.Type) {}
        requireSendable(VideoCheckpoint.self)
    }

    func testVideoCheckpointEventEncoding() throws {
        let video = VideoEvent(
            resolvedBidId: "bid-abc",
            checkpoint: .firstQuartile,
            occurredAt: Date.now,
            opaqueUserId: "user-123",
            placement: Placement(path: "/categories/dairy", position: 1),
            deviceType: .mobile,
            channel: .onsite
        )

        let data = try JSONEncoder().encode(video)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["resolvedBidId"] as? String, "bid-abc")
        XCTAssertEqual(json["eventType"] as? String, "firstQuartile")
        XCTAssertNil(json["errorCode"], "errorCode is only sent with an error event")
        XCTAssertEqual(json["opaqueUserId"] as? String, "user-123")
        XCTAssertEqual((json["placement"] as? [String: Any])?["path"] as? String, "/categories/dairy")
        XCTAssertEqual(json["deviceType"] as? String, "mobile")
        XCTAssertEqual(json["channel"] as? String, "onsite")
        XCTAssertNotNil(json["id"])
        XCTAssertNotNil(json["occurredAt"])
    }

    /// The API requires errorCode when eventType is error, so the error initializer sets both.
    func testVideoErrorEventEncoding() throws {
        let video = VideoEvent(resolvedBidId: "bid-abc", errorCode: 405, occurredAt: Date.now, opaqueUserId: "user-123")

        let data = try JSONEncoder().encode(video)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["eventType"] as? String, "error")
        XCTAssertEqual(json["errorCode"] as? Int, 405)
    }

    /// Queued events are persisted and decoded again on the next launch.
    func testVideoEventItemRoundTrips() throws {
        let item = EventItem.video(VideoEvent(resolvedBidId: "bid-abc", errorCode: 402, occurredAt: Date.now, opaqueUserId: "user-123"))

        let decoded = try JSONDecoder().decode(EventItem.self, from: JSONEncoder().encode(item))

        guard case let .video(video) = decoded else { return XCTFail("expected a video event, got \(decoded)") }
        XCTAssertEqual(video.resolvedBidId, "bid-abc")
        XCTAssertEqual(video.eventType, "error")
        XCTAssertEqual(video.errorCode, 402)
    }

    // MARK: - Events batch with video events

    func testEventsBatchIncludesVideoEvents() throws {
        let video = VideoEvent(resolvedBidId: "bid-abc", checkpoint: .complete, occurredAt: Date.now)
        let events = Events(videoEvents: [video])

        let data = try JSONEncoder().encode(events)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual((json["videoEvents"] as? [Any])?.count, 1)
    }

    // MARK: - EventItem grouping with video events

    /// toItems is how a batch the queue gave up on is read back to unmark its bids; it must
    /// return every event in the body, video events included.
    func testEventsToItemsIncludesVideoEvents() {
        let video = VideoEvent(resolvedBidId: "bid-v", checkpoint: .start, occurredAt: Date.now, opaqueUserId: "u")
        let impression = Event(resolvedBidId: "bid-i", occurredAt: Date.now, opaqueUserId: "u")
        let items = Events(impressions: [impression], videoEvents: [video]).toItems()

        XCTAssertEqual(items.map(\.kind), [.impression, .video])
    }

    func testEventItemGroupsVideoEvents() {
        Topsort.shared.set(opaqueUserId: "test-user")
        let video = VideoEvent(resolvedBidId: "bid-abc", checkpoint: .start, occurredAt: Date.now)
        let impression = Event(entity: Entity(type: .product, id: "p1"), occurredAt: Date.now)

        let items: [EventItem] = [
            .video(video),
            .impression(impression),
        ]

        let events = items.toEvents()

        XCTAssertEqual(events.videoEvents?.count, 1)
        XCTAssertEqual(events.impressions?.count, 1)
    }
}
