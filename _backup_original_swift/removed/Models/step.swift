import Foundation

// MARK: - Auth
struct AuthResponse: Codable {
    let token: String
    let user: UserDto
}

struct UserDto: Codable, Identifiable {
    let id: String
    let name: String
    let email: String
    let connectionCode: String
    let sharingEnabled: Bool
}

struct RegisterRequest: Codable {
    let name: String
    let email: String
    let password: String
}

struct LoginRequest: Codable {
    let email: String
    let password: String
}

// MARK: - Steps
struct SyncStepsRequest: Codable {
    let stepCount: Int
    let date: String
    let isActive: Bool
}

struct MyStepsResponse: Codable {
    let date: String
    let stepCount: Int
    let updatedAt: String?
    let isActive: Bool
    let lastActiveAt: String?
}

// MARK: - Connections
struct ConnectionResponse: Codable, Identifiable {
    let id: String
    let name: String
    let stepCount: Int?
    let isActive: Bool?
    let lastActiveAt: String?
}

struct CreateConnectionRequest: Codable {
    let connectionCode: String
}
