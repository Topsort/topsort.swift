import Foundation
@testable import Topsort

class MockHTTPClient: HTTPClient {
    private let lock = NSLock()
    private var _postCalled = false
    private var _postCallCount = 0
    private var _postData: Data?
    private var _allPostedData: [Data] = []

    var postCalled: Bool {
        lock.withLock { _postCalled }
    }

    var postCallCount: Int {
        lock.withLock { _postCallCount }
    }

    var postData: Data? {
        lock.withLock { _postData }
    }

    var allPostedData: [Data] {
        lock.withLock { _allPostedData }
    }

    var postResult: Result<Data?, HTTPClientError>?

    init(apiKey: String?, postResult: Result<Data?, HTTPClientError>?) {
        self.postResult = postResult
        super.init(apiKey: apiKey)
    }

    private func recordPost(data: Data) {
        lock.withLock {
            _postCalled = true
            _postCallCount += 1
            _postData = data
            _allPostedData.append(data)
        }
    }

    override func asyncPost(url _: URL, data: Data, timeoutInterval _: TimeInterval = 60) async throws(HTTPClientError) -> Data? {
        recordPost(data: data)
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
        recordPost(data: data)
        if let result = postResult {
            callback(result)
        }
    }
}
