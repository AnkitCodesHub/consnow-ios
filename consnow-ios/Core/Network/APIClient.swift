//
//  APIClient.swift
//  Consnow
//
//  iOS equivalent of the Android Retrofit client + AuthInterceptor:
//  - reads the JWT fresh on every request
//  - on 401 clears the session ONLY if the token that failed is still current
//    (same race guard as Android's clearSessionIfToken)
//  - surfaces NestJS error messages ("Invalid connection code", ...)
//

import Foundation

enum APIError: LocalizedError {
    case offline
    case unauthorized
    case server(status: Int, message: String)
    case decoding
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .offline: return "You're offline. Check your connection and try again."
        case .unauthorized: return "Your session expired. Please sign in again."
        case .server(_, let message): return message
        case .decoding: return "Unexpected response from the server."
        case .invalidURL: return "Invalid request."
        }
    }
}

final class APIClient {
    static let shared = APIClient()

    static let baseURL = URL(string: "https://consnow-backend-production.up.railway.app/")!

    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .timedOut,
        .cannotFindHost, .cannotConnectToHost, .dataNotAllowed,
        .internationalRoamingOff, .dnsLookupFailed,
    ]

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        session = URLSession(configuration: config)
    }

    /// Sends a request and decodes the JSON body as `T`.
    func send<T: Decodable>(
        _ method: String,
        _ path: String,
        body: (any Encodable)? = nil,
        query: [URLQueryItem] = [],
        auth: Bool = true,
        as type: T.Type
    ) async throws -> T {
        let data = try await sendRaw(method, path, body: body, query: query, auth: auth)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            #if DEBUG
            print("❌ Decode \(T.self) failed for \(path): \(error)\n\(String(data: data, encoding: .utf8) ?? "")")
            #endif
            throw APIError.decoding
        }
    }

    /// Sends a request and returns the raw body (use when the response isn't needed).
    @discardableResult
    func sendRaw(
        _ method: String,
        _ path: String,
        body: (any Encodable)? = nil,
        query: [URLQueryItem] = [],
        auth: Bool = true
    ) async throws -> Data {
        guard var components = URLComponents(
            url: Self.baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        ) else { throw APIError.invalidURL }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }

        let sentToken = auth ? TokenManager.shared.token : nil
        if let sentToken {
            request.setValue("Bearer \(sentToken)", forHTTPHeaderField: "Authorization")
        }

        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: request)
        } catch let error as URLError where Self.offlineCodes.contains(error.code) {
            throw APIError.offline
        }
        let (data, response) = result
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        #if DEBUG
        print("🌐 \(method) /\(path) → \(status)")
        #endif

        if status == 401 {
            if let sentToken { TokenManager.shared.clearSessionIfToken(sentToken) }
            throw APIError.unauthorized
        }
        guard (200..<300).contains(status) else {
            throw APIError.server(
                status: status,
                message: Self.serverMessage(from: data) ?? "Something went wrong (\(status))."
            )
        }
        return data
    }

    /// NestJS errors look like {"message": "..."} or {"message": ["...", "..."]}.
    private static func serverMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let message = object["message"] as? String { return message }
        if let messages = object["message"] as? [String] { return messages.joined(separator: "\n") }
        return nil
    }
}
