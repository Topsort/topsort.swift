import Foundation
@testable import Topsort

class MockHTTPClient: HTTPClient {
    var postCalled = false
    var postData: Data?
    var postResult: Result<Data?, HTTPClientError>?

    init(apiKey: String?, postResult: Result<Data?, HTTPClientError>?) {
        self.postResult = postResult
        super.init(apiKey: apiKey)
    }

    override func asyncPost(url: URL, data: Data, timeoutInterval: TimeInterval = 60) async throws(HTTPClientError) -> Data? {
        postCalled = true
        postData = data
        switch postResult {
        case let .success(data):
            return data
        case let .failure(error):
            throw error
        case .none:
            return nil
        }
    }
}
