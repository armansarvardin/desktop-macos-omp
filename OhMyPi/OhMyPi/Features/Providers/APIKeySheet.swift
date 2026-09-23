//
//  APIKeySheet.swift
//  OhMyPi
//
//  Created by Arman Sarvardin on 23/9/26.
//

import SwiftUI

/// Stores a provider's API key in `~/.omp/agent/.env`, where the CLI reads it.
struct APIKeySheet: View {
    @Environment(\.dismiss) private var dismiss

    let provider: ProviderStatus
    let onSave: (String) -> Void

    @State private var key = ""

    private var variable: String {
        provider.envVariables.first { !ProviderEnvironment.isOAuthVariable($0) } ?? provider.envVariables.first ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("API key for \(provider.name)", systemImage: "key")
                .font(.headline)

            Text("Saved as `\(variable)` in ~/.omp/agent/.env. The value is written to that file only and never shown again here. A process environment variable with the same name takes precedence.")
                .font(.callout)
                .foregroundStyle(.secondary)

            SecureField(provider.hasKeyInEnvFile ? "Replace existing key" : "Paste key", text: $key)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)

            HStack {
                if provider.hasKeyInEnvFile {
                    Button("Remove Key", role: .destructive) {
                        onSave("")
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func save() {
        guard !key.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        onSave(key)
        dismiss()
    }
}
