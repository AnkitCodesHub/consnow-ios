//
//  RegisterView.swift
//  Consnow
//

import SwiftUI

struct RegisterView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @State private var name = ""
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

                    Text("Create your account")
                        .foregroundColor(.textSecondary)
                        .font(.subheadline)

                    Spacer().frame(height: 20)

                    VStack(spacing: 12) {
                        AuthField(placeholder: "Name", text: $name, kind: .name)
                        AuthField(placeholder: "Email", text: $email, kind: .email)
                        AuthField(placeholder: "Password (min 8 characters)", text: $password, kind: .newPassword)
                    }

                    if let error = authVM.error {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                    }

                    PrimaryButton(title: "Create account", isLoading: authVM.isLoading) {
                        Task { await authVM.register(name: name, email: email, password: password) }
                    }
                    .padding(.top, 8)

                    Button {
                        authVM.clearError()
                        showLogin = true
                    } label: {
                        Text("Already have an account? Sign in")
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
