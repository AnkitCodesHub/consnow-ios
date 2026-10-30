//
//  AuthField.swift
//  Consnow
//

import SwiftUI

struct AuthField: View {
    enum Kind { case name, email, password, newPassword }

    let placeholder: String
    @Binding var text: String
    let kind: Kind

    var body: some View {
        Group {
            switch kind {
            case .password, .newPassword:
                SecureField(placeholder, text: $text)
                    .textContentType(kind == .password ? .password : .newPassword)
            case .email:
                TextField(placeholder, text: $text)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            case .name:
                TextField(placeholder, text: $text)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
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

struct PrimaryButton: View {
    let title: String
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.accent)
                    .frame(height: 56)
                if isLoading {
                    ProgressView().tint(.black)
                } else {
                    Text(title)
                        .foregroundColor(.black)
                        .fontWeight(.semibold)
                }
            }
        }
        .disabled(isLoading)
    }
}
