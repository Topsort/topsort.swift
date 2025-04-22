# topsort.swift

## Install

### Using package.swift

```swift
let package = Package(
    ...
    dependencies: [
        .package(url: "https://github.com/Topsort/topsort.swift.git", from: "1.0.0"),
    ]
    ...
)
```

## Usage

### Setup

```swift
import SwiftUI
import Topsort

@main
struct MyApp: App {
    init() {
        Topsort.shared.configure(apiKey: "your-api-key", auctionsTimeout: 20)
    }
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

### Auctions

View all auction models and their definitions in the [Swift package link](https://github.com/Topsort/topsort.swift/blob/main/Sources/Topsort/Models/Auctions.swift).

```swift
import SwiftUI
import Topsort

let products = AuctionProducts(ids: ["p_dsad", "p_dvra", "p_oplf", "p_gjfo"])

let category = AuctionCategory(id: "c_fdfa")

let auctions = [
    Auction(type: "banners", slots: 1, slotId: "home-banner", device: "mobile", category: category),
    Auction(type: "listings", slots: 2, device: "mobile", products: products)
]
let result: AuctionResponse = await Topsort.shared.executeAuctions(auctions: auctions)

```

### Events

View all event models and their definitions in the [Swift package link](https://github.com/Topsort/topsort.swift/blob/main/Sources/Topsort/Models/Events.swift).

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
            Topsort.shared.track(impression: self.event())
        }
        .onTapGesture {
            Topsort.shared.track(click: self.event())
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
                Topsort.shared.track(purchase: event)
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
        TopsortBanner(bannerAuctionBuilder: .init(slotId: "slotId", deviceType: "device"))
            .contentMode(.fill)
            .onNoWinners({
                // callback when no winners are returned
            })
            .onError({ error in
                // callback when an error occurs
            })
            .onImageLoad({
                // callback when image is loaded
            })
            .buttonClickedAction({ response in
                // callback when button is clicked
            })
            .frame(maxHeight: 50)
            .clipped()
    }
}
```

This code will display a banner, send an impression event when the banner is shown, and send a click event when the banner is clicked. Inside the callback, you can add logic to execute when the banner is clicked, such as redirecting to the product page.
