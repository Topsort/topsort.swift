import Foundation
import Topsort

class SharedValues: ObservableObject {
    @Published var resolvedBidId: String?
    @Published var loading: Bool
    @Published var urlString: String?
    @Published var response: AuctionResponse?

    init() {
        resolvedBidId = nil
        loading = true
        urlString = nil
        response = nil
    }

    public func setResolvedBidIdAndUrlFromResponse() {
        guard let response = self.response else {
            return
        }
        let results = response.results

        guard let winners = results.first?.winners else {
            return
        }
        guard let winner = winners.first else {
            return
        }
        guard let asset = winner.asset?.first else {
            return
        }
        resolvedBidId = winner.resolvedBidId
        urlString = asset.url
    }
}
