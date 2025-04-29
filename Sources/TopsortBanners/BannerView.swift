import Foundation
import SwiftUI
import Topsort

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
        return Auction(type: "banners", slots: 1, slotId: slotId, device: deviceType, products: products, category: category, searchQuery: searchQuery, geoTargeting: geoTargeting)
    }
}

extension BannerAuctionBuilder: With {
    public func with(products value: AuctionProducts?) -> Self {
        return with(path: \.products, to: value)
    }

    public func with(category value: AuctionCategory?) -> Self {
        return with(path: \.category, to: value)
    }

    public func with(searchQuery value: String?) -> Self {
        return with(path: \.searchQuery, to: value)
    }

    public func with(geoTargeting value: AuctionGeoTargeting?) -> Self {
        return with(path: \.geoTargeting, to: value)
    }
}

public typealias ButtonClicked = Action<AuctionResponse?>
public typealias OnError = Action<BannerError>

public struct TopsortBanner: View {
    @StateObject var viewModel = ViewModel()
    @State var imageUrl: URL? = nil

    var buttonClickedAction: ButtonClicked? = nil
    var onImageLoad: UnitAction? = nil
    var onError: OnError? = nil
    var onNoWinners: UnitAction? = nil
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

    private func buttonClicked() {
        if let rab = viewModel.resolvedBidId {
            let event = Event(resolvedBidId: rab, occurredAt: Date.now)
            topsort.track(click: event)
        }
        buttonClickedAction?(viewModel.response)
    }

    public var body: some View {
        VStack {
            if viewModel.loading {
                ProgressView()
            } else {
                if let image_url = self.viewModel.urlString {
                    if let url = URL(string: image_url) {
                        AsyncImage(url: self.imageUrl) { phase in
                            switch phase {
                            case .empty:
                                ProgressView()
                            case let .success(image):
                                let _ = self.onImageLoad?()
                                GeometryReader { geo in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: self.contentMode)
                                        .frame(maxWidth: geo.size.width, maxHeight: geo.size.height)
                                        .clipped()
                                }
                            case let .failure(error):
                                let _ = self.onError?(.unknown(error: error))
                                EmptyView()
                            @unknown default:
                                EmptyView()
                            }
                        }
                        .onAppear {
                            self.imageUrl = url
                        }
                        .onDisappear {
                            self.imageUrl = nil
                        }
                    }
                }
            }
        }
        .onTapGesture {
            self.buttonClicked()
        }
        .task(id: auction) {
            await self.viewModel.executeAuctions(auction: self.auction, topsort: self.topsort, onError: self.onError, onNoWinners: self.onNoWinners)
        }
    }
}

extension TopsortBanner: With {
    public func buttonClickedAction(_ value: ButtonClicked?) -> Self {
        return with(path: \.buttonClickedAction, to: value)
    }

    public func onError(_ value: OnError?) -> Self {
        return with(path: \.onError, to: value)
    }

    public func onImageLoad(_ value: UnitAction?) -> Self {
        return with(path: \.onImageLoad, to: value)
    }

    public func contentMode(_ value: ContentMode) -> Self {
        return with(path: \.contentMode, to: value)
    }

    public func onNoWinners(_ value: UnitAction?) -> Self {
        return with(path: \.onNoWinners, to: value)
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

            let event = Event(resolvedBidId: winner.resolvedBidId, occurredAt: Date.now)
            topsort.track(impression: event)
        }
    }
}
