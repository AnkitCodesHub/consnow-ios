//
//  LoginView.swift
//  MyApp
//
//  Created by Ankit Raj on 12/10/26.
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

            VStack(spacing: 20) {
                Spacer()

                Text("Consnow")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(.accent)

                Text("Welcome back")
                    .foregroundColor(.textSecondary)
                    .font(.subheadline)

                Spacer().frame(height: 20)

                VStack(spacing: 12) {
                    TextField("Email", text: $email)
                    
                        
                        .padding()
                        .foregroundColor(.textPrimary)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        )

                    SecureField("Password", text: $password)
                        .padding()
                        .foregroundColor(.textPrimary)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        )
                }

                if let error = authVM.error {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }

                Button {
                    Task { await authVM.login(email: email, password: password) }
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.cardBackground)
                            .frame(height: 56)
                        if authVM.isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Text("Sign in")
                                .foregroundColor(.textSecondary)
                                .fontWeight(.medium)
                        }
                    }
                }
                .padding(.top, 8)

                Button {
                    showLogin = false
                } label: {
                    Text("New here? Create an account")
                        .foregroundColor(.accent)
                        .font(.subheadline)
                }

                Spacer()
            }
            .padding(.horizontal, 24)
        }
    }
}
