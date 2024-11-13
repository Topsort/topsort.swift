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

    override func asyncPost(url _: URL, data: Data) async throws -> Data? {
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
    
    override func post(url _: URL, data: Data, callback: @escaping (Result<Data?, HTTPClientError>) -> Void) {
        postCalled = true
        postData = data
        switch postResult {
        case let .success(data):
            callback(.success(data))
        case let .failure(error):
            callback(.failure(HTTPClientError.unknown(error: error, data: ErrorData(data: data))))
        case .none:
            callback(.failure(HTTPClientError.statusCode(code: 400, data: ErrorData(data: data))))
        }
    }
}
