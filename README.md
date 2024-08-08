# Analytics.swift

## Install

### Using package.swift

```swift
let package = Package(
    ...
    dependencies: [
        .package(url: "https://github.com/Topsort/analytics.swift.git", from: "1.0.0"),
    ]
    ...
)
```

## Usage

### Setup

```swift
import SwiftUI
import Topsort_Analytics

@main
struct MyApp: App {
    init() {
        Analytics.shared.configure(apiKey: "your-api-key", url: "https://api.topsort.com")
    }
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

### Auctions

View all auction models and their definitions in the [Swift package link](https://github.com/Topsort/analytics.swift/blob/main/Sources/Topsort-Analytics/Models/Auctions.swift).

```swift
import SwiftUI
import Topsort_Analytics

let products = AuctionProducts(ids: ["p_dsad", "p_dvra", "p_oplf", "p_gjfo"])

let category = AuctionCategory(id: "c_fdfa")

let auctions = [
    Auction(type: "banners", slots: 1, slotId: "home-banner", device: "mobile", category: category),
    Auction(type: "listings", slots: 2, device: "mobile", products: products)
]
let result: AuctionResponse = await Analytics.shared.executeAuctions(auctions: auctions)

```

### Events

View all event models and their definitions in the [Swift package link](https://github.com/Topsort/analytics.swift/blob/main/Sources/Topsort-Analytics/Models/Events.swift).

#### Impression & click

```swift
struct Product {
    let id: String
    let image_url: URL
    let name: String
    let resolvedBidId: String?
    let price: Double
}

struct ProductView: View {
    @State
    public var product: Product

    private func event() -> Event {
        var event: Event;
        if (self.product.resolvedBidId != nil) {
            event = Event(resolvedBidId: self.product.resolvedBidId!, occurredAt: Date.now)
        } else {
            event = Event(entity: Entity(type: EntityType.product, id: self.product.id), occurredAt: Date.now)
        }
        return event
    }

    var body: some View {
        VStack {
            AsyncImage(url: self.product.image_url)
            Text(self.product.name)
        }
        .onAppear {
            Analytics.shared.track(impression: self.event())
        }
        .onTapGesture {
            Analytics.shared.track(click: self.event())
        }
    }
}
```

#### Purchase

```swift
struct ContentView: View {
    var myProduct = Product(id: "123", image_url: URL(string: "https://loremflickr.com/640/480?lock=1234")!, name: "My Product", resolvedBidId: "123", price: 12.00)
    var body: some View {
        VStack {
            ProductView(product: myProduct)
            Button("Purchase me!") {
                let item = PurchaseItem(productId: myProduct.id, unitPrice: myProduct.price)
                let event = PurchaseEvent(items: [item], occurredAt: Date.now)
                Analytics.shared.track(purchase: event)
            }
        }
        .padding()
    }
}
```

### Banners

```swift
import TopsortBanners

struct ContentView: View {
    var body: some View {
        TopsortBanner(
            apiKey: "API_KEY",
            url: "https://api.topsort.com/v2",
            width: widht,
            height: height,
            slotId: "slotId",
            deviceType: "device"
        ) { response in
            // function to execute when banner is clicked
        }
    }
}
```

This code will display a banner, send an impression event when the banner is shown, and send a click event when the banner is clicked. Inside the callback, you can add logic to execute when the banner is clicked, such as redirecting to the product page.
