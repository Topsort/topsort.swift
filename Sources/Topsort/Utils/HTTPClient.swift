import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

enum HTTPClientError: Error {
    case unknown(error: Error, data: ErrorData?)
    case statusCode(code: Int, data: ErrorData?)
}

enum ErrorData {
    case data(Data)
    case topsortError(TopsortError)
}

extension ErrorData {
    init?(data: Data?) {
        guard let data = data else { return nil }
        if let topsortError = try? JSONDecoder().decode(TopsortError.self, from: data) {
            self = .topsortError(topsortError)
        } else {
            self = .data(data)
        }
    }
}

extension HTTPClientError {
    func isRetriable() -> Bool {
        switch self {
        case .unknown:
            return true
        case let .statusCode(code, _):
            return code != 400
        }
    }
}

class HTTPClient {
    public var apiKey: String?
    private let session: URLSession
    public init(apiKey: String?) {
        self.apiKey = apiKey
        session = URLSession(configuration: .ephemeral, delegate: nil, delegateQueue: nil)
    }

    public func asyncPost(url: URL, data: Data) async throws -> Data? {
        var request = newRequest(url: url, method: "POST")
        request.httpBody = data
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HTTPClientError.unknown(error: NSError(domain: "HTTPClient", code: 0, userInfo: nil), data: ErrorData(data: data))
        }
        if httpResponse.statusCode >= 400 {
            throw HTTPClientError.statusCode(code: httpResponse.statusCode, data: ErrorData(data: data))
        }
        return data
    }
}

extension HTTPClient {
    private func newRequest(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        request.httpMethod = method
        request.addValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.addValue("analytics-swift/\(__analytics_version)", forHTTPHeaderField: "User-Agent")
        if let apiKey = apiKey {
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    public func post(url: URL, data: Data, callback: @escaping (Result<Data?, HTTPClientError>) -> Void) {
        var request = newRequest(url: url, method: "POST")
        request.httpBody = data
        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                callback(.failure(HTTPClientError.unknown(error: error, data: ErrorData(data: data))))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                callback(.failure(HTTPClientError.unknown(error: NSError(domain: "HTTPClient", code: 0, userInfo: nil), data: ErrorData(data: data))))
                return
            }
            if httpResponse.statusCode >= 400 {
                callback(.failure(HTTPClientError.statusCode(code: httpResponse.statusCode, data: ErrorData(data: data))))
                return
            }
            callback(.success(data))
        }
        task.resume()
    }
}
