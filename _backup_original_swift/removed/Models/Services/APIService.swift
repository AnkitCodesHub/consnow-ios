//
//  APIService.swift
//  MyApp
//
//  Created by Ankit Raj on 12/10/26.
//
import Foundation
import Combine

class APIService {
    
    static let shared = APIService()
    private init() {}
    
    private let baseURL = "https://consnow-backend.onrender.com/" // ← put your NestJS URL here
    
    private var token: String? {
        UserDefaults.standard.string(forKey: "auth_token")
    }
    
    // MARK: - Core request method
    private func request<T: Codable>(
        endpoint: String,
        method: String = "GET",
        body: Encodable? = nil
    ) async throws -> T {
        print("🔥 API CALL FIRED: \(endpoint)")
        guard let url = URL(string: baseURL + endpoint) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        if let body = body {
            request.httpBody = try JSONEncoder().encode(body)
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        print("📦 API Response: \(String(data: data, encoding: .utf8) ?? "nil")")
        return try JSONDecoder().decode(T.self, from: data)
    }
    
    // MARK: - Auth
    func register(name: String, email: String, password: String) async throws -> AuthResponse {
        let body = RegisterRequest(name: name, email: email, password: password)
        return try await request(endpoint: "auth/register", method: "POST", body: body)
    }
    
    func login(email: String, password: String) async throws -> AuthResponse {
        let body = LoginRequest(email: email, password: password)
        return try await request(endpoint: "auth/login", method: "POST", body: body)
    }
    
    // MARK: - Steps
    func syncSteps(stepCount: Int, date: String, isActive: Bool) async throws {
        let body = SyncStepsRequest(stepCount: stepCount, date: date, isActive: isActive)
        let _: [String: String] = try await request(
            endpoint: "steps/sync",
            method: "PUT",
            body: body
        )
    }
    
    // MARK: - Connections
    func getConnections() async throws -> [ConnectionResponse] {
        return try await request(endpoint: "connections")
    }
    
    func createConnection(code: String) async throws -> ConnectionResponse {
        let body = CreateConnectionRequest(connectionCode: code)
        return try await request(endpoint: "connections", method: "POST", body: body)
    }
}

