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

### With SwiftUI

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
