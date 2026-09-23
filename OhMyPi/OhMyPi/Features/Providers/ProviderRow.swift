//
//  ProviderRow.swift
//  OhMyPi
//
//  Created by Arman Sarvardin on 23/9/26.
//

import SwiftUI

/// One provider: enablement toggle, credential status and actions.
struct ProviderRow: View {
    let provider: ProviderStatus
    let model: ProvidersStateModel
    let onModels: () -> Void
    let onAPIKey: () -> Void

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { provider.isEnabled },
            set: { model.setEnabled($0, for: provider.id) }
        )
    }

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: enabledBinding)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .help(provider.isEnabled ? "Disable provider" : "Enable provider")

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(verbatim: provider.name)
                        .fontWeight(.medium)
                    Text(verbatim: provider.id)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                HStack(spacing: 6) {
                    credentialPill
                    if !provider.models.isEmpty {
                        StatusPill(
                            title: modelsTitle,
                            systemImage: "cpu",
                            tint: provider.scope == .all ? .secondary : .blue
                        )
                    }
                }
            }
            .opacity(provider.isEnabled ? 1 : 0.55)

            Spacer()

            if !provider.models.isEmpty {
                Button("Models…", action: onModels)
            }

            if provider.supportsAPIKey {
                Button(provider.hasKeyInEnvFile ? "API Key…" : "Set API Key…", action: onAPIKey)
            }

            if provider.isAvailable {
                Button(provider.isAuthenticated ? "Log In Again" : "Log In…") {
                    Task { await model.login(provider.id) }
                }
                .disabled(model.isBusy)
            }
        }
        .controlSize(.small)
        .padding(.vertical, 2)
    }

    // MARK: - Subviews

    @ViewBuilder
    private var credentialPill: some View {
        if provider.isAuthenticated {
            StatusPill(title: "signed in", systemImage: "checkmark.seal", tint: .green)
        } else if provider.hasKeyInEnvFile {
            StatusPill(title: "key in .env", systemImage: "key", tint: .green)
        } else if !provider.models.isEmpty {
            StatusPill(title: "credentials found", systemImage: "checkmark", tint: .green)
        } else {
            StatusPill(title: "no credentials", systemImage: "key.slash", tint: .secondary)
        }
    }

    private var modelsTitle: String {
        switch provider.scope {
        case .all: "\(provider.models.count) models"
        case .selected: "\(provider.enabledModelCount) of \(provider.models.count) models"
        }
    }
}
