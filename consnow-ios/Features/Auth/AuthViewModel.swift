//
//  AuthViewModel.swift
//  Consnow
//

import Foundation
import Combine

final class AuthViewModel: ObservableObject {
    @Published private(set) var isLoggedIn = TokenManager.shared.isLoggedIn
    @Published private(set) var currentUser: UserDto? = TokenManager.shared.user
    @Published var isLoading = false
    @Published var error: String?

    private let tokenManager = TokenManager.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Follow the session, so a 401 anywhere in the app returns to Login.
        tokenManager.$token
            .combineLatest(tokenManager.$user)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] token, user in
                self?.isLoggedIn = token != nil && user != nil
                self?.currentUser = user
            }
            .store(in: &cancellables)
    }

    func login(email: String, password: String) async {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty, !password.isEmpty else {
            error = "Enter your email and password."
            return
        }
        await authenticate {
            try await APIClient.shared.send(
                "POST", "auth/login",
                body: LoginRequest(email: email, password: password),
                auth: false,
                as: AuthResponse.self
            )
        }
    }

    func register(name: String, email: String, password: String) async {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { error = "Enter your name."; return }
        guard email.contains("@") else { error = "Enter a valid email."; return }
        guard password.count >= 8 else { error = "Password must be at least 8 characters."; return }
        await authenticate {
            try await APIClient.shared.send(
                "POST", "auth/register",
                body: RegisterRequest(name: name, email: email, password: password),
                auth: false,
                as: AuthResponse.self
            )
        }
    }

    func logout() {
        SessionCleanup.run()
    }

    /// App Store requires in-app account deletion (guideline 5.1.1(v)).
    func deleteAccount() async -> Bool {
        isLoading = true
        defer { isLoading = false }
        do {
            try await APIClient.shared.sendRaw("DELETE", "auth/me")
            SessionCleanup.run()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func clearError() { error = nil }

    private func authenticate(_ call: () async throws -> AuthResponse) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let response = try await call()
            tokenManager.saveSession(token: response.token, user: response.user)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Everything that must be wiped on logout / account deletion / 401.
enum SessionCleanup {
    static func run() {
        StepTracker.shared.stop(resetState: true)
        ConnectionsStore.shared.clear()
        TokenManager.shared.clearSession()
    }
}
