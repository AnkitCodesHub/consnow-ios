//
//  SettingsView.swift
//  Consnow
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            List {
                if let user = authVM.currentUser {
                    Section("Account") {
                        LabeledContent("Name", value: user.name)
                        LabeledContent("Email", value: user.email)
                        LabeledContent("Your code", value: user.connectionCode)
                    }
                }

                Section {
                    Button("Log out") {
                        authVM.logout()
                        dismiss()
                    }
                }

                Section {
                    Button("Delete account", role: .destructive) {
                        confirmDelete = true
                    }
                    .disabled(authVM.isLoading)
                } footer: {
                    Text("Permanently deletes your account, your step history and all your connections.")
                }

                if let error = authVM.error {
                    Section {
                        Text(error).foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Delete your Consnow account?",
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button("Delete account", role: .destructive) {
                    Task {
                        if await authVM.deleteAccount() { dismiss() }
                    }
                }
            } message: {
                Text("This can't be undone.")
            }
        }
    }
}
