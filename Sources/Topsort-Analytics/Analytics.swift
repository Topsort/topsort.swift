// The Swift Programming Language
// https://docs.swift.org/swift-book

import Foundation

private let TOPSORT_URL = "https://api.topsort.ai/v2/events"
private let TOPSORT_TOKEN = ""

func sendEvents(events: Events) async throws {
    let url = URL(string: TOPSORT_URL)!
    var request = URLRequest(url: url)
    request.setValue(String(format: "Bearer %s", TOPSORT_TOKEN), forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpMethod = "POST"
    request.httpBody = try! JSONSerialization.data(withJSONObject: events, options: [])
    
    let (data, response) = try! await URLSession.shared.data(for: request)
    
    if let httpResponse = response as? HTTPURLResponse {
        if (httpResponse.statusCode != 200) {
            let jsonError = try! JSONSerialization.jsonObject(with: data) as! [String: String]
            throw TopsortError(jsonObject: jsonError)
        }
    }
}
