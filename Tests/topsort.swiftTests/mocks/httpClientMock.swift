import Foundation
@testable import Topsort

class MockHTTPClient: HTTPClient {
    var postCalled = false
    var postCallCount = 0
    var postData: Data?
    var allPostedData: [Data] = []
    var postResult: Result<Data?, HTTPClientError>?

    init(apiKey: String?, postResult: Result<Data?, HTTPClientError>?) {
        self.postResult = postResult
        super.init(apiKey: apiKey)
    }

    override func asyncPost(url _: URL, data: Data, timeoutInterval _: TimeInterval = 60) async throws(HTTPClientError) -> Data? {
        postCalled = true
        postCallCount += 1
        postData = data
        allPostedData.append(data)
        switch postResult {
        case let .success(data):
            return data
        case let .failure(error):
            throw error
        case .none:
            return nil
        }
    }

    override func post(url _: URL, data: Data, callback: @escaping (Result<Data?, HTTPClientError>) -> Void) {
        postCalled = true
        postCallCount += 1
        postData = data
        allPostedData.append(data)
        if let result = postResult {
            callback(result)
        }
    }
}
