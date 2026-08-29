import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

public enum HTTPClientError: Error {
    case unknown(error: Error, data: ErrorData?)
    case statusCode(code: Int, data: ErrorData?)
}

public enum ErrorData {
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
    /// Whether the failure is worth another attempt.
    ///
    /// Client errors (4xx) are permanent: the same payload against the same endpoint will
    /// fail identically every time, so retrying only burns the retry budget and keeps the
    /// batch on disk. The exceptions are 408 and 429, which both explicitly invite a later
    /// attempt. Server errors (5xx) and transport failures are treated as transient.
    func isRetriable() -> Bool {
        switch self {
        case .unknown:
            return true
        case let .statusCode(code, _):
            switch code {
            case 408, 429:
                return true
            case 400 ..< 500:
                return false
            default:
                return true
            }
        }
    }
}

class HTTPClient {
    var apiKey: String?
    private let session: URLSession
    /// `configuration` exists so tests can install a `URLProtocol`; production always uses the
    /// ephemeral default.
    init(apiKey: String?, configuration: URLSessionConfiguration = .ephemeral) {
        self.apiKey = apiKey
        session = URLSession(configuration: configuration, delegate: nil, delegateQueue: nil)
    }

    func asyncPost(url: URL, data: Data, timeoutInterval: TimeInterval = 60) async throws(HTTPClientError) -> Data? {
        var request = newRequest(url: url, method: "POST")
        request.httpBody = data
        request.timeoutInterval = timeoutInterval
        let (data, response): (Data?, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw HTTPClientError.unknown(error: error, data: nil)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HTTPClientError.unknown(error: NSError(domain: "HTTPClient", code: 0, userInfo: nil), data: ErrorData(data: data))
        }
        if httpResponse.statusCode >= 400 {
            throw HTTPClientError.statusCode(code: httpResponse.statusCode, data: ErrorData(data: data))
        }
        return data
    }

    func post(url: URL, data: Data, callback: @escaping (Result<Data?, HTTPClientError>) -> Void) {
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

    func newRequest(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        request.httpMethod = method
        request.addValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.addValue("analytics-swift/\(__analytics_version)", forHTTPHeaderField: "User-Agent")
        if let apiKey = apiKey {
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        return request
    }
}
