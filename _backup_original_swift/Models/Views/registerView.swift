//
//  registerView.swift
//  MyApp
//
//  Created by Ankit Raj on 12/10/26.
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

            VStack(spacing: 20) {
                Spacer()

                Text("Consnow")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(.accent)

                Text("Create your account")
                    .foregroundColor(.textSecondary)
                    .font(.subheadline)

                Spacer().frame(height: 20)

                // Fields
                VStack(spacing: 12) {
                    field(placeholder: "Name", text: $name, secure: false)
                    field(placeholder: "Email", text: $email, secure: false)
                    field(placeholder: "Password", text: $password, secure: true)
                }

                if let error = authVM.error {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }

                Button {
                    Task { await authVM.register(name: name, email: email, password: password) }
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.cardBackground)
                            .frame(height: 56)
                        if authVM.isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Text("Create account")
                                .foregroundColor(.textSecondary)
                                .fontWeight(.medium)
                        }
                    }
                }
                .padding(.top, 8)

                Button {
                    showLogin = true
                } label: {
                    Text("Already have an account? Sign in")
                        .foregroundColor(.accent)
                        .font(.subheadline)
                }

                Spacer()
            }
            .padding(.horizontal, 24)
        }
    }

    func field(placeholder: String, text: Binding<String>, secure: Bool) -> some View {
        Group {
            if secure {
                SecureField(placeholder, text: text)
            } else {
                TextField(placeholder, text: text)

            }
        }
        .padding()
        .foregroundColor(.textPrimary)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.3), lineWidth: 1)
        )
    }
}
