//
//  ProvidersStateModel.swift
//  OhMyPi
//
//  Created by Arman Sarvardin on 23/9/26.
//

import AppKit
import Foundation
import Observation

/// Providers the CLI knows about: credentials, enablement (`disabledProviders`)
/// and which of their models are allowed (`enabledModels`).
@Observable
final class ProvidersStateModel {
    enum Phase: Equatable {
        case idle
        case loading
        case saving
        case refreshingCatalog
        case loggingIn(providerId: String)
        case failed(String)
    }

    // MARK: - Stored properties

    private(set) var providers: [ProviderStatus] = []
    private(set) var phase: Phase = .idle
    private(set) var message: String?
    /// Login prompts (callback URL paste) waiting for the user.
    private(set) var pendingUIRequest: ExtensionUIRequest?

    private let configClient: OmpConfigClient
    private let catalogService: ModelCatalogService
    private let launcher: RpcLauncher
    private let envFile: EnvFileStore

    private var savedSnapshot: [ProviderStatus] = []
    /// Scoped (object) entries in `disabledProviders` / `enabledModels`, written back untouched.
    private var scopedDisabledEntries: [JSONValue] = []
    private var scopedEnabledEntries: [JSONValue] = []
    /// Free-form `enabledModels` patterns the UI does not model (globs, fuzzy names).
    private(set) var extraEnabledPatterns: [String] = []
    private var loginAgent: HeadlessAgent?

    // MARK: - Initialization

    init(
        configClient: OmpConfigClient,
        catalogService: ModelCatalogService,
        launcher: RpcLauncher,
        envFile: EnvFileStore = EnvFileStore()
    ) {
        self.configClient = configClient
        self.catalogService = catalogService
        self.launcher = launcher
        self.envFile = envFile
    }

    // MARK: - Computed properties

    var hasChanges: Bool {
        providers.map(\.isEnabled) != savedSnapshot.map(\.isEnabled)
            || providers.map(\.scope) != savedSnapshot.map(\.scope)
    }

    var isBusy: Bool {
        switch phase {
        case .idle, .failed: false
        default: true
        }
    }

    func provider(_ id: String) -> ProviderStatus? {
        providers.first { $0.id == id }
    }

    // MARK: - Loading

    func load() async {
        phase = .loading
        message = nil

        do {
            async let disabledValue = configClient.get("disabledProviders")
            async let enabledValue = configClient.get("enabledModels")
            async let catalogValue = catalogService.models()
            async let loginValue = fetchLoginProviders()
            let (disabledConfig, enabledConfig, catalog, loginProviders) = try await (disabledValue, enabledValue, catalogValue, loginValue)

            let disabledEntries = disabledConfig.value.arrayValue ?? []
            let enabledEntries = enabledConfig.value.arrayValue ?? []
            scopedDisabledEntries = disabledEntries.filter { $0.stringValue == nil }
            scopedEnabledEntries = enabledEntries.filter { $0.stringValue == nil }

            let disabled = Set(disabledEntries.compactMap(\.stringValue))
            let enabledPatterns = enabledEntries.compactMap(\.stringValue)
            let definedVariables = envFile.definedVariables()
            let modelsByProvider = Dictionary(grouping: catalog, by: \.provider)

            var scopes: [String: ProviderStatus.ModelScope] = [:]
            var extras: [String] = []
            for pattern in enabledPatterns {
                guard let slash = pattern.firstIndex(of: "/") else {
                    extras.append(pattern)
                    continue
                }
                let provider = String(pattern[..<slash])
                let rest = String(pattern[pattern.index(after: slash)...])
                if rest == "*" {
                    scopes[provider] = .all
                } else if rest.contains("*") {
                    extras.append(pattern)
                } else if case .selected(var ids) = scopes[provider] ?? .selected([]) {
                    ids.insert(rest)
                    scopes[provider] = .selected(ids)
                }
            }
            extraEnabledPatterns = extras
            let restrictsModels = !enabledPatterns.isEmpty

            var seen = Set<String>()
            var statuses: [ProviderStatus] = []
            for login in loginProviders where seen.insert(login.id).inserted {
                statuses.append(makeStatus(
                    id: login.id, name: login.name, available: login.available, authenticated: login.authenticated,
                    models: modelsByProvider[login.id] ?? [], disabled: disabled, definedVariables: definedVariables,
                    scopes: scopes, restrictsModels: restrictsModels
                ))
            }
            // Providers that only appear in the catalog (custom models.yml entries, AWS chains).
            for provider in modelsByProvider.keys.sorted() where seen.insert(provider).inserted {
                statuses.append(makeStatus(
                    id: provider, name: provider, available: true, authenticated: true,
                    models: modelsByProvider[provider] ?? [], disabled: disabled, definedVariables: definedVariables,
                    scopes: scopes, restrictsModels: restrictsModels
                ))
            }
            // Disabled providers with no login entry still need a row so they can be re-enabled.
            for provider in disabled.sorted() where seen.insert(provider).inserted {
                statuses.append(makeStatus(
                    id: provider, name: provider, available: false, authenticated: false,
                    models: [], disabled: disabled, definedVariables: definedVariables,
                    scopes: scopes, restrictsModels: restrictsModels
                ))
            }

            providers = statuses.sorted { lhs, rhs in
                (lhs.hasCredentials ? 0 : 1, lhs.isEnabled ? 0 : 1, lhs.name.lowercased())
                    < (rhs.hasCredentials ? 0 : 1, rhs.isEnabled ? 0 : 1, rhs.name.lowercased())
            }
            savedSnapshot = providers
            phase = .idle
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func refreshCatalog() async {
        phase = .refreshingCatalog
        do {
            try await catalogService.refresh()
            await load()
            message = "Catalog refreshed"
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: - Editing

    func setEnabled(_ isEnabled: Bool, for providerId: String) {
        update(providerId) { $0.isEnabled = isEnabled }
    }

    func setScope(_ scope: ProviderStatus.ModelScope, for providerId: String) {
        update(providerId) { $0.scope = scope }
    }

    func setModel(_ modelId: String, enabled: Bool, for providerId: String) {
        update(providerId) { provider in
            var ids: Set<String>
            switch provider.scope {
            case .all: ids = Set(provider.models.map(\.id))
            case .selected(let existing): ids = existing
            }
            if enabled { ids.insert(modelId) } else { ids.remove(modelId) }
            provider.scope = .selected(ids)
        }
    }

    func discardChanges() {
        providers = savedSnapshot
    }

    // MARK: - Saving

    func save() async {
        phase = .saving

        let disabled = providers.filter { !$0.isEnabled }.map { JSONValue.string($0.id) } + scopedDisabledEntries

        var enabledPatterns: [String] = []
        let everythingAllowed = providers.allSatisfy { $0.scope == .all } && extraEnabledPatterns.isEmpty
        if !everythingAllowed {
            for provider in providers {
                switch provider.scope {
                case .all:
                    enabledPatterns.append("\(provider.id)/*")
                case .selected(let ids):
                    enabledPatterns += ids.sorted().map { "\(provider.id)/\($0)" }
                }
            }
            enabledPatterns += extraEnabledPatterns
        }
        let enabled = enabledPatterns.map(JSONValue.string) + scopedEnabledEntries

        do {
            try await configClient.set("disabledProviders", OmpConfigClient.array(disabled))
            try await configClient.set("enabledModels", OmpConfigClient.array(enabled))
            savedSnapshot = providers
            message = "Saved. Applies to sessions started from now on."
            phase = .idle
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: - Credentials

    /// Writes the key to `~/.omp/agent/.env`, which the CLI reads on start.
    func setAPIKey(_ key: String, for providerId: String) {
        guard let variable = ProviderEnvironment.variables(for: providerId).first(where: { !ProviderEnvironment.isOAuthVariable($0) }) else { return }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            if trimmed.isEmpty {
                try envFile.remove(variable)
            } else {
                try envFile.set(variable, to: trimmed)
            }
            update(providerId) { $0.hasKeyInEnvFile = !trimmed.isEmpty }
            message = trimmed.isEmpty ? "\(variable) removed from .env" : "\(variable) saved to \(envFile.fileURL.path)"
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Runs the CLI's OAuth login through a headless agent; prompts surface as `pendingUIRequest`.
    func login(_ providerId: String) async {
        phase = .loggingIn(providerId: providerId)
        message = nil

        do {
            let agent = try await HeadlessAgent.start(launcher: launcher) { [weak self] frame in
                self?.handleLoginEvent(frame)
            }
            loginAgent = agent
            defer {
                agent.stop()
                loginAgent = nil
                pendingUIRequest = nil
            }

            try await agent.client.request(.login(providerId: providerId))
            message = "Logged in to \(provider(providerId)?.name ?? providerId)"
            await load()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func respond(to request: ExtensionUIRequest, with response: ExtensionUIResponse) {
        loginAgent?.client.respond(to: request.id, with: response)
        if pendingUIRequest?.id == request.id {
            pendingUIRequest = nil
        }
    }

    // MARK: - Private

    private func fetchLoginProviders() async throws -> [RpcLoginProvider] {
        let agent = try await HeadlessAgent.start(launcher: launcher)
        defer { agent.stop() }
        return try await agent.loginProviders()
    }

    private func makeStatus(
        id: String, name: String, available: Bool, authenticated: Bool, models: [RpcModel],
        disabled: Set<String>, definedVariables: Set<String>,
        scopes: [String: ProviderStatus.ModelScope], restrictsModels: Bool
    ) -> ProviderStatus {
        ProviderStatus(
            id: id,
            name: name,
            isAvailable: available,
            isAuthenticated: authenticated,
            hasKeyInEnvFile: ProviderEnvironment.variables(for: id).contains { definedVariables.contains($0) },
            isEnabled: !disabled.contains(id),
            models: models.sorted { $0.name.lowercased() < $1.name.lowercased() },
            scope: restrictsModels ? (scopes[id] ?? .selected([])) : .all
        )
    }

    private func handleLoginEvent(_ frame: JSONValue) {
        guard frame["type"]?.stringValue == "extension_ui_request",
              let request = ExtensionUIRequest(frame: frame)
        else { return }

        switch request.method {
        case .openURL(let url, let instructions):
            if let url = URL(string: url) {
                NSWorkspace.shared.open(url)
            }
            message = instructions ?? "Finish signing in in your browser, then paste the callback here if asked."
        case .input, .select, .confirm, .editor:
            pendingUIRequest = request
        case .notify(let text, _):
            message = text
        case .cancel(let targetId):
            if pendingUIRequest?.id == targetId { pendingUIRequest = nil }
        default:
            break
        }
    }

    private func update(_ providerId: String, _ mutate: (inout ProviderStatus) -> Void) {
        guard let index = providers.firstIndex(where: { $0.id == providerId }) else { return }
        mutate(&providers[index])
    }
}
