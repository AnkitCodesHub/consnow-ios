//
//  AuthViewModel.swift
//  MyApp
//
//  Created by Ankit Raj on 12/10/26.
//

import Foundation
import Combine

@MainActor
class AuthViewModel: ObservableObject {
    
    @Published var isLoggedIn = false
    @Published var isLoading = false
    @Published var error: String? = nil
    @Published var currentUser: UserDto? = nil
    
    init() {
        // Check if token already exists (auto-login)
        if let token = UserDefaults.standard.string(forKey: "auth_token"),
           !token.isEmpty {
            isLoggedIn = true
        }
    }
    
    func login(email: String, password: String) async {
        isLoading = true
        error = nil
        do {
            let response = try await APIService.shared.login(email: email, password: password)
            UserDefaults.standard.set(response.token, forKey: "auth_token")
            UserDefaults.standard.set(response.user.id, forKey: "user_id")
            UserDefaults.standard.set(response.user.name, forKey: "user_name")
            currentUser = response.user
            isLoggedIn = true
        } catch {
            self.error = "Login failed. Check your credentials."
        }
        isLoading = false
    }
    
    func register(name: String, email: String, password: String) async {
        isLoading = true
        error = nil
        do {
            let response = try await APIService.shared.register(
                name: name, email: email, password: password
            )
            UserDefaults.standard.set(response.token, forKey: "auth_token")
            UserDefaults.standard.set(response.user.id, forKey: "user_id")
            UserDefaults.standard.set(response.user.name, forKey: "user_name")
            currentUser = response.user
            isLoggedIn = true
        } catch {
            self.error = "Registration failed. Try again."
        }
        isLoading = false
    }
    
    func logout() {
        UserDefaults.standard.removeObject(forKey: "auth_token")
        UserDefaults.standard.removeObject(forKey: "user_id")
        UserDefaults.standard.removeObject(forKey: "user_name")
        isLoggedIn = false
        currentUser = nil
    }
}
