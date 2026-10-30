//
//  LoginView.swift
//  Consnow
//

import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @State private var email = ""
    @State private var password = ""
    @Binding var showLogin: Bool

    var body: some View {
        ZStack {
            Color.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    Spacer().frame(height: 80)

                    Text("Consnow")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundColor(.accent)

                    Text("Welcome back")
                        .foregroundColor(.textSecondary)
                        .font(.subheadline)

                    Spacer().frame(height: 20)

                    VStack(spacing: 12) {
                        AuthField(placeholder: "Email", text: $email, kind: .email)
                        AuthField(placeholder: "Password", text: $password, kind: .password)
                    }

                    if let error = authVM.error {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                    }

                    PrimaryButton(title: "Sign in", isLoading: authVM.isLoading) {
                        Task { await authVM.login(email: email, password: password) }
                    }
                    .padding(.top, 8)

                    Button {
                        authVM.clearError()
                        showLogin = false
                    } label: {
                        Text("New here? Create an account")
                            .foregroundColor(.accent)
                            .font(.subheadline)
                    }
                }
                .padding(.horizontal, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }
}
