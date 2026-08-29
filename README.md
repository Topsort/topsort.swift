# topsort.swift

[![Build](https://github.com/Topsort/topsort.swift/actions/workflows/test.yml/badge.svg)](https://github.com/Topsort/topsort.swift/actions/workflows/test.yml)
[![Coverage](https://img.shields.io/endpoint?url=https://topsort.github.io/topsort.swift/coverage.json)](https://github.com/Topsort/topsort.swift/actions/workflows/test.yml)
[![Swift 6 toolchain](https://img.shields.io/badge/Swift-6%20toolchain%20(Xcode%2016+)-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%2015+%20|%20macOS%2012+-blue.svg)](https://github.com/Topsort/topsort.swift)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![SPM Compatible](https://img.shields.io/badge/SPM-Compatible-brightgreen.svg)](https://swift.org/package-manager/)

Swift SDK for [Topsort](https://www.topsort.com) retail media: auctions, event tracking, and banner ads.

**Two libraries, zero external dependencies:**
- **`Topsort`** — Core SDK for running auctions and tracking events (impressions, clicks, purchases)
- **`TopsortBanners`** — Drop-in SwiftUI banner component with built-in auction, rendering, and tracking

## Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Topsort/topsort.swift.git", from: "1.1.0"), // x-release-please-version
]
```

Then add the targets you need:

```swift
.target(
    name: "YourApp",
    dependencies: [
        "Topsort",          // Core SDK (auctions + events)
        "TopsortBanners",   // Optional: SwiftUI banner component
    ]
)
```

Or in Xcode: **File > Add Package Dependencies** and paste `https://github.com/Topsort/topsort.swift.git`.

## Quick Start

### 1. Configure the SDK

Call `configure()` once at app launch, before any tracking or auction calls:

```swift
import Topsort

@main
struct MyApp: App {
    init() {
        var config = Configuration(apiKey: "your-api-key")
        config.auctionsTimeout = 20       // Optional: auction timeout in seconds (default: 60)
        config.flushAt = 30               // Optional: event batch size (default: 30)
        config.flushInterval = 30         // Optional: flush interval in seconds (default: 30)
        config.logLevel = .warning        // Optional: .none, .error, .warning, .debug
        do {
            try Topsort.shared.configure(config)
        } catch {
            // Invalid url, flushAt < 1 or flushInterval <= 0. Until this succeeds,
            // track() drops events and executeAuctions() throws .notConfigured.
            print("Topsort not configured: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

### 2. Run Auctions

Request sponsored listings or banner placements (1-5 auctions per request):

```swift
let products = try AuctionProducts(ids: ["p_dsad", "p_dvra", "p_oplf", "p_gjfo"])
let category = AuctionCategory(id: "c_fdfa")

let auctions = [
    Auction(type: "banners", slots: 1, slotId: "home-banner", device: "mobile", category: category),
    Auction(type: "listings", slots: 2, device: "mobile", products: products),
]

let response = try await Topsort.shared.executeAuctions(auctions: auctions)

for result in response.results {
    for winner in result.winners {
        print("Winner: \(winner.id), bid: \(winner.resolvedBidId)")
    }
}
```

See all auction models in [`Auctions.swift`](Sources/Topsort/Models/Auctions.swift).

### 3. Track Events

Track impressions, clicks, purchases, and page views. Events are batched automatically and flushed every 30 seconds or when the batch reaches 30 events; see [How Events Are Delivered](#how-events-are-delivered).

#### Impressions & Clicks

```swift
// For promoted results (from an auction)
let event = Event(resolvedBidId: winner.resolvedBidId, occurredAt: Date.now)

// For organic results (no auction)
let event = Event(entity: Entity(type: .product, id: product.id), occurredAt: Date.now)

Topsort.shared.track(impression: event)  // on view appear
Topsort.shared.track(click: event)       // on tap
```

Report each impression once per `resolvedBidId`, when the creative is on screen. Both initializers also take optional context: `placement`, `page`, `deviceType`, `channel`, `additionalAttribution` (a product or vendor `Entity` to attribute purchases to besides the ad's own; only meaningful with `resolvedBidId`) and, for clicks, `clickType` (`"product"`, `"like"`, `"add-to-cart"`).

#### Purchases

```swift
let items = [
    PurchaseItem(productId: "p1", unitPrice: 9.99, quantity: 2),
    PurchaseItem(productId: "p2", unitPrice: 14.50),
]
let purchase = PurchaseEvent(items: items, occurredAt: Date.now)
Topsort.shared.track(purchase: purchase)
```

`PurchaseItem` also takes `vendorId` for vendor-level attribution.

#### Page Views

```swift
let pageview = PageViewEvent(page: Page(type: "category", pageId: "shoes"), occurredAt: Date.now)
Topsort.shared.track(pageview: pageview)
```

#### Manual Flush

Force-send all queued events (e.g., before a critical navigation):

```swift
Topsort.shared.flush()
```

See all event models in [`Events.swift`](Sources/Topsort/Models/Events.swift).

### 4. Banners (SwiftUI)

Drop-in banner component that handles the full lifecycle: auction, image loading, impression tracking (when the image has loaded), and click tracking.

```swift
import TopsortBanners

TopsortBanner(bannerAuctionBuilder: .init(slotId: "home-banner", deviceType: "mobile"))
    .contentMode(.fill)
    .onNoWinners {
        // No ads available for this placement
    }
    .onError { error in
        // Handle auction or image loading error
    }
    .onImageLoad {
        // Banner image rendered (impression tracked automatically)
    }
    .buttonClickedAction { response in
        // User tapped the banner (click tracked automatically)
        // Navigate to the product page
    }
    .frame(maxHeight: 200)
    .clipped()
```

## Architecture

```
Topsort (core)              TopsortBanners (UI)
├── Topsort.shared          └── TopsortBanner (SwiftUI View)
│   ├── configure()             ├── Runs auction
│   ├── track(impression:)      ├── Loads & renders image
│   ├── track(click:)           ├── Tracks impression on image load
│   ├── track(purchase:)        └── Tracks click on tap
│   ├── track(pageview:)
│   ├── flush()
│   └── executeAuctions()
├── EventManager (queue, batch, retry)
├── AuctionManager (async/await)
└── HTTPClient (ephemeral URLSession)
```

**Event pipeline**: Events are queued in memory, batched by count or interval, and flushed to the Topsort API in POSTs of at most 500 events. Failed requests are retried with exponential backoff (up to 50 retries, 20 min max). Events persist across app restarts in `Application Support`.

**Offline support**: The SDK detects network connectivity. Requests are paused when offline and automatically flushed when the connection is restored.

**Lifecycle management**: Events are flushed and persisted to disk when the app enters background or terminates.

## Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `apiKey` | `String` | Required | Your Topsort API key |
| `url` | `String?` | `nil` | Custom API base URL, including the version path — e.g. `https://proxy.example.com/v2` (defaults to `https://api.topsort.com/v2`) |
| `auctionsTimeout` | `TimeInterval?` | `60` | Auction request timeout in seconds |
| `flushAt` | `Int` | `30` | Number of events that triggers a flush (at least 1) |
| `flushInterval` | `TimeInterval` | `30` | Seconds between automatic flushes (greater than 0) |
| `logLevel` | `LogLevel` | `.warning` | Log verbosity: `.none`, `.error`, `.warning`, `.debug` |

## How Events Are Delivered

A `track` call appends the event to an in-memory queue and returns; nothing happens on the caller's thread. The queue is sent when it reaches `flushAt`, every `flushInterval`, on `flush()`, when the app goes to the background or terminates, and when connectivity returns. Sends are retried with exponential backoff, across being offline and across launches: the queue and every unacknowledged batch are written to `Application Support` (debounced, and synchronously on background/terminate). Events are never dropped for being old; the only drops are the ones [Error Handling](#error-handling) describes.

## Error Handling

`configure()` throws `ConfigurationError` for an invalid `url`, `flushAt < 1` or `flushInterval <= 0`; until it succeeds, `track()` logs and drops the event and `executeAuctions()` throws `AuctionError.notConfigured`.

Events the SDK gives up on are logged and dropped (queue eviction at `.warning`, once per episode; the rest at `.error`): rejected by the API with a 4xx (408 and 429 are retried instead), retried 50 times without success, evicted as the oldest once the queue passes 5,000 events, or impossible to serialize (a non-finite `unitPrice`, say — only the offending event is dropped, not its batch).

`executeAuctions()` throws `AuctionError`:

```swift
do {
    let response = try await Topsort.shared.executeAuctions(auctions: auctions)
} catch {
    switch error {
    case let .http(error):                       // transport failure or 4xx/5xx status
        print("Auction request failed: \(error)")
    case let .invalidNumberAuctions(count):      // must be 1–5
        print("Sent \(count) auctions")
    case .serializationError, .deserializationError, .emptyResponse:
        print("Unexpected payload: \(error)")
    case .notConfigured:
        print("Call configure() first")
    }
}
```

## Testing

`TopsortBanner` accepts any `TopsortProtocol` conformer, so your tests can inject a stub that returns a canned `AuctionResponse` and records tracked events. The SDK ships no mock. A minimal stub:

```swift
final class StubTopsort: TopsortProtocol {
    var opaqueUserId = "test-user"
    var isConfigured = true
    var response: AuctionResponse
    var tracked: [Event] = []
    init(response: AuctionResponse) { self.response = response }
    func set(opaqueUserId: String?) {}
    func configure(_: Configuration) throws {}
    func track(impression event: Event) { tracked.append(event) }
    func track(click event: Event) { tracked.append(event) }
    func track(purchase _: PurchaseEvent) {}
    func track(pageview _: PageViewEvent) {}
    func flush() {}
    func executeAuctions(auctions _: [Auction]) async throws(AuctionError) -> AuctionResponse { response }
}

let banner = TopsortBanner(bannerAuctionBuilder: builder, topsort: StubTopsort(response: canned))
```

## Requirements

- Swift 6 toolchain (Xcode 16+)
- iOS 15.0+ / macOS 12.0+
- No external dependencies

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, code style, and PR guidelines.

## Security

See [SECURITY.md](SECURITY.md) for vulnerability reporting.

## License

MIT. See [LICENSE](LICENSE).
