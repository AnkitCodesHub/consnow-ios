//
//  DTOs.swift
//  Consnow
//
//  Request/response shapes, matched 1:1 to consnow-backend (NestJS).
//  `nonisolated` keeps them usable off the main actor (project default is MainActor).
//

import Foundation

// MARK: - Auth  (POST /auth/register, /auth/login, /auth/refresh, DELETE /auth/me)

nonisolated struct AuthResponse: Codable {
    let token: String
    let user: UserDto
}

nonisolated struct RefreshResponse: Codable {
    let token: String
}

nonisolated struct UserDto: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let email: String
    let connectionCode: String
    let sharingEnabled: Bool
}

nonisolated struct RegisterRequest: Codable {
    let name: String
    let email: String
    let password: String
}

nonisolated struct LoginRequest: Codable {
    let email: String
    let password: String
}

// MARK: - Steps  (PUT /steps/sync, GET /steps/me, GET /steps/user/:userId)

nonisolated struct SyncStepsRequest: Codable {
    let stepCount: Int
    let date: String        // local YYYY-MM-DD
    let isActive: Bool
    let lastStepAt: Int64?  // device epoch ms of the most recent step (omitted when nil)
}

nonisolated struct MyStepsResponse: Codable {
    let date: String
    let stepCount: Int
    let updatedAt: String?
    let isActive: Bool
    let lastActiveAt: String?
}

nonisolated struct PeerStepsResponse: Codable, Equatable {
    let userId: String
    let userName: String
    let date: String
    let stepCount: Int
    let updatedAt: String?
    let isActive: Bool
    let lastActiveAt: String?
}

// MARK: - Activity  (GET /activity/peer/:userId)

nonisolated struct ActivityResponse: Codable, Equatable {
    let userId: String?
    let unlockedAt: String?
    let isLocked: Bool
    let isOnline: Bool
    /// When the server last heard from the phone (optional: older backends don't send it).
    let lastSeenAt: String?
}

// MARK: - Activity reporting  (PUT /activity/unlock, /activity/lock, /activity/heartbeat)

nonisolated struct ActivityEventRequest: Codable {
    let occurredAt: Int64   // device epoch ms of the transition
}

// MARK: - Push  (POST /devices/apns-token)

nonisolated struct ApnsTokenRequest: Codable {
    let token: String
    let environment: String  // "sandbox" | "production"
}

// MARK: - Connections  (GET /connections, POST /connections)

nonisolated struct ConnectionDto: Codable, Identifiable, Hashable {
    let id: String          // connection id (NOT the friend's user id)
    let status: String
    let peer: PeerDto
    let createdAt: String?
}

nonisolated struct PeerDto: Codable, Hashable {
    let id: String          // friend's user id — use this for /steps/user and /activity/peer
    let name: String
    let sharingEnabled: Bool
}

nonisolated struct CreateConnectionRequest: Codable {
    let connectionCode: String
}
