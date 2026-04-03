import Foundation
import SwiftUI
import Topsort

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

private let imageSession = URLSession(configuration: .ephemeral)

struct RemoteImage: View {
    let url: URL
    let contentMode: ContentMode
    var onSuccess: (() -> Void)?
    var onFailure: ((Error) -> Void)?

    @State private var image: Image?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                GeometryReader { geo in
                    image
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .frame(maxWidth: geo.size.width, maxHeight: geo.size.height)
                        .clipped()
                }
            } else if failed {
                EmptyView()
            } else {
                ProgressView()
            }
        }
        .task(id: url) {
            do {
                let (data, _) = try await imageSession.data(from: url)
                guard let swiftUIImage = Self.makeImage(from: data) else {
                    failed = true
                    onFailure?(NSError(domain: "RemoteImage", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid image data"]))
                    return
                }
                image = swiftUIImage
                onSuccess?()
            } catch {
                failed = true
                onFailure?(error)
            }
        }
    }

    private static func makeImage(from data: Data) -> Image? {
        #if canImport(UIKit)
            guard let uiImage = UIImage(data: data) else { return nil }
            return Image(uiImage: uiImage)
        #elseif canImport(AppKit)
            guard let nsImage = NSImage(data: data) else { return nil }
            return Image(nsImage: nsImage)
        #else
            return nil
        #endif
    }
}

public enum BannerError: Error {
    case auction(error: AuctionError)
    case unknown(error: Error)
}

public struct BannerAuctionBuilder {
    let slotId: String
    let deviceType: String
    var products: AuctionProducts?
    var category: AuctionCategory?
    var searchQuery: String?
    var geoTargeting: AuctionGeoTargeting?
    public init(slotId: String,
                deviceType: String)
    {
        self.slotId = slotId
        self.deviceType = deviceType
    }

    public func build() -> Auction {
        Auction(type: "banners", slots: 1, slotId: slotId, device: deviceType, products: products, category: category, searchQuery: searchQuery, geoTargeting: geoTargeting)
    }
}

extension BannerAuctionBuilder: With {
    public func with(products value: AuctionProducts?) -> Self {
        with(path: \.products, to: value)
    }

    public func with(category value: AuctionCategory?) -> Self {
        with(path: \.category, to: value)
    }

    public func with(searchQuery value: String?) -> Self {
        with(path: \.searchQuery, to: value)
    }

    public func with(geoTargeting value: AuctionGeoTargeting?) -> Self {
        with(path: \.geoTargeting, to: value)
    }
}

public typealias ButtonClicked = Action<AuctionResponse?>
public typealias OnError = Action<BannerError>

public struct TopsortBanner: View {
    @StateObject var viewModel = ViewModel()

    var buttonClickedAction: ButtonClicked?
    var onImageLoad: UnitAction?
    var onError: OnError?
    var onNoWinners: UnitAction?
    let auction: Auction
    var contentMode: ContentMode = .fill
    let topsort: TopsortProtocol

    public init(
        bannerAuctionBuilder: BannerAuctionBuilder,
        topsort: TopsortProtocol = Topsort.shared
    ) {
        self.topsort = topsort
        auction = bannerAuctionBuilder.build()
    }

    private func trackImpression(resolvedBidId: String) {
        let event = Event(resolvedBidId: resolvedBidId, occurredAt: Date.now, opaqueUserId: topsort.opaqueUserId)
        topsort.track(impression: event)
    }

    private func buttonClicked() {
        if let rab = viewModel.resolvedBidId {
            let event = Event(resolvedBidId: rab, occurredAt: Date.now, opaqueUserId: topsort.opaqueUserId)
            topsort.track(click: event)
        }
        buttonClickedAction?(viewModel.response)
    }

    public var body: some View {
        VStack {
            if viewModel.loading {
                ProgressView()
            } else {
                if let image_url = viewModel.urlString,
                   let url = URL(string: image_url)
                {
                    let capturedBidId = viewModel.resolvedBidId
                    RemoteImage(
                        url: url,
                        contentMode: contentMode,
                        onSuccess: {
                            if let bidId = capturedBidId {
                                trackImpression(resolvedBidId: bidId)
                            }
                            onImageLoad?()
                        },
                        onFailure: { error in onError?(.unknown(error: error)) }
                    )
                }
            }
        }
        .onTapGesture {
            buttonClicked()
        }
        .task(id: auction) {
            await viewModel.executeAuctions(auction: auction, topsort: topsort, onError: onError, onNoWinners: onNoWinners)
        }
    }
}

extension TopsortBanner: With {
    public func buttonClickedAction(_ value: ButtonClicked?) -> Self {
        with(path: \.buttonClickedAction, to: value)
    }

    public func onError(_ value: OnError?) -> Self {
        with(path: \.onError, to: value)
    }

    public func onImageLoad(_ value: UnitAction?) -> Self {
        with(path: \.onImageLoad, to: value)
    }

    public func contentMode(_ value: ContentMode) -> Self {
        with(path: \.contentMode, to: value)
    }

    public func onNoWinners(_ value: UnitAction?) -> Self {
        with(path: \.onNoWinners, to: value)
    }
}

extension TopsortBanner {
    @MainActor
    class ViewModel: ObservableObject {
        @Published private(set) var resolvedBidId: String? = nil
        @Published private(set) var loading: Bool = true
        @Published private(set) var urlString: String? = nil
        @Published private(set) var response: AuctionResponse?

        func executeAuctions(auction: Auction, topsort: TopsortProtocol, onError: OnError?, onNoWinners: UnitAction?) async {
            let response: AuctionResponse
            do {
                response = try await topsort.executeAuctions(auctions: [auction])
            } catch {
                loading = false
                onError?(.auction(error: error))
                return
            }

            self.response = response
            loading = false
            if response.results.first?.winners.isEmpty ?? true {
                onNoWinners?()
            }

            resolvedBidId = nil
            urlString = nil

            guard let winner = self.response?.results.first?.winners.first else { return }
            guard let asset = winner.asset?.first else { return }
            resolvedBidId = winner.resolvedBidId
            urlString = asset.url
        }
    }
}
