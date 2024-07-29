import Foundation
@testable import Topsort_Analytics

class MockHTTPClient: HTTPClient {
    var postCalled = false
    var postData: Data?
    var postResult: Result<Data?, HTTPClientError>?

    init(apiKey: String?, postResult: Result<Data?, HTTPClientError>?) {
        self.postResult = postResult
        super.init(apiKey: apiKey)
    }

    override func asyncPost(url: URL, data: Data) async throws -> Data? {
        postCalled = true
        postData = data
        switch postResult {
        case .success(let data):
            return data
        case .failure(let error):
            throw error
        case .none:
            return nil
        }
    }
}
