//
//  Providers.swift
//  OhMyPi
//
//  Created by Arman Sarvardin on 23/9/26.
//

import SwiftUI

/// Enable or disable providers, sign in, store API keys and pick which of
/// their models the CLI may use.
struct Providers: View {
    @Environment(\.ompConfigClient) private var configClient
    @Environment(\.modelCatalogService) private var catalogService
    @Environment(\.rpcLauncher) private var rpcLauncher

    @State private var providersStateModel: ProvidersStateModel?
    @State private var query = ""
    @State private var showOnlyConfigured = true
    @State private var modelsProvider: ProviderStatus?
    @State private var apiKeyProvider: ProviderStatus?

    var body: some View {
        Group {
            if let providersStateModel {
                content(providersStateModel)
            } else {
                ProgressView()
            }
        }
        .task {
            guard providersStateModel == nil else { return }
            let model = ProvidersStateModel(configClient: configClient, catalogService: catalogService, launcher: rpcLauncher)
            providersStateModel = model
            await model.load()
        }
    }

    // MARK: - Content

    private func content(_ model: ProvidersStateModel) -> some View {
        VStack(spacing: .zero) {
            HStack {
                TextField("Search providers", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)

                Toggle("Only with credentials", isOn: $showOnlyConfigured)
                    .toggleStyle(.checkbox)

                Spacer()

                Button("Refresh Catalog") {
                    Task { await model.refreshCatalog() }
                }
                .disabled(model.isBusy)
            }
            .padding(12)

            Divider()

            List {
                ForEach(visibleProviders(model)) { provider in
                    ProviderRow(
                        provider: provider,
                        model: model,
                        onModels: { modelsProvider = provider },
                        onAPIKey: { apiKeyProvider = provider }
                    )
                }

                if !model.extraEnabledPatterns.isEmpty {
                    Section("Other enabledModels patterns (kept as is)") {
                        ForEach(model.extraEnabledPatterns, id: \.self) { pattern in
                            Text(verbatim: pattern)
                                .font(.system(.callout, design: .monospaced))
                        }
                    }
                }
            }
            .listStyle(.inset)
            .overlay {
                if model.providers.isEmpty, model.phase == .loading {
                    ProgressView("Asking omp for providers…")
                }
            }

            Divider()

            footer(model)
        }
        .sheet(item: $modelsProvider) { provider in
            ProviderModelsSheet(providerId: provider.id, model: model)
        }
        .sheet(item: $apiKeyProvider) { provider in
            APIKeySheet(provider: provider) { key in
                model.setAPIKey(key, for: provider.id)
            }
        }
        .sheet(item: loginRequest(model)) { request in
            ExtensionUIRequestSheet(request: request) { response in
                model.respond(to: request, with: response)
            }
        }
    }

    private func visibleProviders(_ model: ProvidersStateModel) -> [ProviderStatus] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        return model.providers.filter { provider in
            (!showOnlyConfigured || provider.hasCredentials || !provider.isEnabled)
                && (needle.isEmpty || provider.name.lowercased().contains(needle) || provider.id.contains(needle))
        }
    }

    private func loginRequest(_ model: ProvidersStateModel) -> Binding<ExtensionUIRequest?> {
        Binding(
            get: { model.pendingUIRequest },
            set: { newValue in
                if newValue == nil, let request = model.pendingUIRequest {
                    model.respond(to: request, with: .cancelled)
                }
            }
        )
    }

    private func footer(_ model: ProvidersStateModel) -> some View {
        HStack(spacing: 12) {
            switch model.phase {
            case .idle:
                Text(model.message ?? "Enablement and model lists apply to sessions started after saving. Keys go to ~/.omp/agent/.env.")
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            case .loading:
                ProgressView().controlSize(.small)
                Text("Reading providers…").foregroundStyle(.secondary)
            case .saving:
                ProgressView().controlSize(.small)
                Text("Writing config…").foregroundStyle(.secondary)
            case .refreshingCatalog:
                ProgressView().controlSize(.small)
                Text("Refreshing model catalog…").foregroundStyle(.secondary)
            case .loggingIn(let providerId):
                ProgressView().controlSize(.small)
                Text(model.message ?? "Signing in to \(providerId)…").foregroundStyle(.secondary).lineLimit(2)
            case .failed(let text):
                Label(text, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            Spacer()

            Button("Reload") {
                Task { await model.load() }
            }
            .disabled(model.isBusy)

            Button("Discard") {
                model.discardChanges()
            }
            .disabled(!model.hasChanges)

            Button("Save") {
                Task { await model.save() }
            }
            .keyboardShortcut("s", modifiers: .command)
            .buttonStyle(.borderedProminent)
            .disabled(!model.hasChanges || model.isBusy)
        }
        .font(.callout)
        .padding(12)
        .background(.bar)
    }
}

#Preview {
    Providers()
        .withPreviewEnvironment()
        .frame(width: 860, height: 600)
}
