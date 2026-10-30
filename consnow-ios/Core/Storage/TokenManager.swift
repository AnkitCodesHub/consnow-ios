//
//  TokenManager.swift
//  Consnow
//
//  Same role as Android's TokenManager: single source of truth for the session.
//  JWT lives in the Keychain; the (non-secret) user profile in UserDefaults.
//

import Foundation
import Combine

final class TokenManager: ObservableObject {
    static let shared = TokenManager()

    @Published private(set) var token: String?
    @Published private(set) var user: UserDto?

    var isLoggedIn: Bool { token != nil && user != nil }

    private let tokenKey = "jwt"
    private let userKey = "current_user"
    private let lastRefreshKey = "token_last_refresh"
    private let defaults = UserDefaults.standard

    private init() {
        // The first Swift build stored the token in UserDefaults without the user's
        // connection code. Drop those keys; affected testers just sign in once more.
        for legacy in ["auth_token", "user_id", "user_name"] {
            defaults.removeObject(forKey: legacy)
        }

        token = KeychainStore.read(tokenKey)
        if let data = defaults.data(forKey: userKey) {
            user = try? JSONDecoder().decode(UserDto.self, from: data)
        }
        // Keychain survives app deletion; UserDefaults doesn't. A leftover token
        // from a previous install without a profile is not a usable session.
        if token != nil && user == nil {
            KeychainStore.delete(tokenKey)
            token = nil
        }
    }

    func saveSession(token: String, user: UserDto) {
        KeychainStore.save(token, for: tokenKey)
        if let data = try? JSONEncoder().encode(user) {
            defaults.set(data, forKey: userKey)
        }
        defaults.set(Date(), forKey: lastRefreshKey)
        self.token = token
        self.user = user
    }

    /// Swap in a refreshed token, but only if the session hasn't changed meanwhile.
    func replaceToken(_ newToken: String, ifCurrent oldToken: String) {
        guard token == oldToken else { return }
        KeychainStore.save(newToken, for: tokenKey)
        defaults.set(Date(), forKey: lastRefreshKey)
        token = newToken
    }

    func clearSession() {
        KeychainStore.delete(tokenKey)
        defaults.removeObject(forKey: userKey)
        defaults.removeObject(forKey: lastRefreshKey)
        token = nil
        user = nil
    }

    /// Only clear if the token that got the 401 is still the current one
    /// (prevents a late 401 from wiping a freshly issued token).
    func clearSessionIfToken(_ failedToken: String) {
        if token == failedToken { clearSession() }
    }

    /// Sliding session: the backend issues 30-day tokens; refresh at most once a day.
    func refreshIfNeeded() async {
        guard let current = token else { return }
        if let last = defaults.object(forKey: lastRefreshKey) as? Date,
           Date().timeIntervalSince(last) < 24 * 3600 { return }
        do {
            let response = try await APIClient.shared.send(
                "POST", "auth/refresh", as: RefreshResponse.self
            )
            replaceToken(response.token, ifCurrent: current)
        } catch {
            // offline or server hiccup: try again next launch
        }
    }
}
