# topsort.swift

[![Build](https://github.com/Topsort/topsort.swift/actions/workflows/test.yml/badge.svg)](https://github.com/Topsort/topsort.swift/actions/workflows/test.yml)
[![Swift 5.3+](https://img.shields.io/badge/Swift-5.3+-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%2015+%20|%20macOS%2012+%20|%20tvOS%2011+%20|%20watchOS%207.1+-blue.svg)](https://github.com/Topsort/topsort.swift)
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
    .package(url: "https://github.com/Topsort/topsort.swift.git", from: "1.0.0"),
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
        try! Topsort.shared.configure(config)
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

Track impressions, clicks, and purchases. Events are batched automatically and flushed every 30 seconds or when the batch reaches 30 events.

#### Impressions & Clicks

```swift
// For promoted results (from an auction)
let event = Event(resolvedBidId: winner.resolvedBidId, occurredAt: Date.now)

// For organic results (no auction)
let event = Event(entity: Entity(type: .product, id: product.id), occurredAt: Date.now)

Topsort.shared.track(impression: event)  // on view appear
Topsort.shared.track(click: event)       // on tap
```

#### Purchases

```swift
let items = [
    PurchaseItem(productId: "p1", unitPrice: 9.99, quantity: 2),
    PurchaseItem(productId: "p2", unitPrice: 14.50),
]
let purchase = PurchaseEvent(items: items, occurredAt: Date.now)
Topsort.shared.track(purchase: purchase)
```

#### Manual Flush

Force-send all queued events (e.g., before a critical navigation):

```swift
Topsort.shared.flush()
```

See all event models in [`Events.swift`](Sources/Topsort/Models/Events.swift).

### 4. Banners (SwiftUI)

Drop-in banner component that handles the full lifecycle: auction, image loading, impression tracking (on render), and click tracking.

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
│   ├── track(click:)           ├── Tracks impression on render
│   ├── track(purchase:)        └── Tracks click on tap
│   ├── flush()
│   └── executeAuctions()
├── EventManager (queue, batch, retry)
├── AuctionManager (async/await)
└── HTTPClient (ephemeral URLSession)
```

**Event pipeline**: Events are queued in memory, batched by count or interval, and flushed to the Topsort API. Failed requests are retried with exponential backoff (up to 50 retries, 20 min max). Events persist across app restarts via plist storage.

**Offline support**: The SDK detects network connectivity. Requests are paused when offline and automatically flushed when the connection is restored.

**Lifecycle management**: Events are flushed and persisted to disk when the app enters background or terminates.

## Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `apiKey` | `String` | Required | Your Topsort API key |
| `url` | `String?` | `nil` | Custom API base URL (defaults to `https://api.topsort.com/v2`) |
| `auctionsTimeout` | `TimeInterval?` | `60` | Auction request timeout in seconds |
| `flushAt` | `Int` | `30` | Number of events that triggers a flush |
| `flushInterval` | `TimeInterval` | `30` | Seconds between automatic flushes |
| `logLevel` | `LogLevel` | `.warning` | Log verbosity: `.none`, `.error`, `.warning`, `.debug` |

## Testing

The SDK is designed for testability. Inject `MockTopsort` (conforming to `TopsortProtocol`) to test your code without network calls:

```swift
let mock = MockTopsort(executeAuctionsMockResponse: mockResponse)
let banner = TopsortBanner(bannerAuctionBuilder: builder, topsort: mock)
```

## Requirements

- Swift 5.3+
- iOS 15.0+ / macOS 12.0+ / tvOS 11.0+ / watchOS 7.1+
- No external dependencies

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, code style, and PR guidelines.

## Security

See [SECURITY.md](SECURITY.md) for vulnerability reporting.

## License

MIT. See [LICENSE](LICENSE).
