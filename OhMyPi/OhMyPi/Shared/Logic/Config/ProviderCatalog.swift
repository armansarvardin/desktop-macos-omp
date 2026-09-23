//
//  ProviderCatalog.swift
//  OhMyPi
//
//  Created by Arman Sarvardin on 23/9/26.
//

import Foundation

// MARK: - Provider status

/// One provider as the app presents it: login state, enablement and its models.
nonisolated struct ProviderStatus: Identifiable, Hashable, Sendable {
    /// Which of a provider's catalog models are allowed by `enabledModels`.
    enum ModelScope: Hashable, Sendable {
        case all
        case selected(Set<String>)
    }

    var id: String
    var name: String
    var isAvailable: Bool
    var isAuthenticated: Bool
    /// One of the provider's env vars is set in `~/.omp/agent/.env`.
    var hasKeyInEnvFile: Bool
    var isEnabled: Bool
    var models: [RpcModel]
    var scope: ModelScope

    var envVariables: [String] {
        ProviderEnvironment.variables(for: id)
    }

    var supportsAPIKey: Bool {
        envVariables.contains { !ProviderEnvironment.isOAuthVariable($0) }
    }

    var hasCredentials: Bool {
        isAuthenticated || hasKeyInEnvFile || !models.isEmpty
    }

    var enabledModelCount: Int {
        switch scope {
        case .all: models.count
        case .selected(let ids): models.filter { ids.contains($0.id) }.count
        }
    }
}

/// `get_login_providers` entry.
nonisolated struct RpcLoginProvider: Decodable, Sendable, Hashable, Identifiable {
    var id: String
    var name: String
    var available: Bool
    var authenticated: Bool
}

// MARK: - Model catalog

/// Reads the CLI's model catalog (`omp models ls --json`), which only lists
/// models whose provider has credentials and is not disabled.
nonisolated struct ModelCatalogService: Sendable {
    let models: @Sendable () async throws -> [RpcModel]
    let refresh: @Sendable () async throws -> Void

    static func live(settings: @escaping @Sendable () -> LaunchSettings = { LaunchSettings.current() }) -> ModelCatalogService {
        ModelCatalogService(
            models: {
                let launch = settings()
                let output = try await ShellCommand.run(
                    executable: launch.executable,
                    arguments: ["models", "ls", "--json"],
                    useLoginShell: launch.useLoginShell
                )
                guard output.succeeded else {
                    throw ShellCommand.Failure.nonZeroExit(output.exitCode, output.stderr)
                }
                guard
                    let start = output.stdout.firstIndex(of: "{"),
                    let data = String(output.stdout[start...]).data(using: .utf8)
                else {
                    throw RpcError.malformedFrame("models output was not JSON")
                }
                let payload = try JSONDecoder().decode(JSONValue.self, from: data)
                return try payload["models"]?.decoded(as: [RpcModel].self) ?? []
            },
            refresh: {
                let launch = settings()
                let output = try await ShellCommand.run(
                    executable: launch.executable,
                    arguments: ["models", "refresh"],
                    useLoginShell: launch.useLoginShell
                )
                guard output.succeeded else {
                    throw ShellCommand.Failure.nonZeroExit(output.exitCode, output.stderr)
                }
            }
        )
    }

    static let `default` = ModelCatalogService.live()
}

// MARK: - Env file

/// The `~/.omp/agent/.env` file the CLI reads API keys from.
nonisolated struct EnvFileStore: Sendable {
    var fileURL: URL = SessionPaths.agentRoot.appending(path: ".env")

    /// Names of variables defined in the file; values are never read into the app.
    func definedVariables() -> Set<String> {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }

        return Set(
            text.split(separator: "\n").compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("#"), let equals = trimmed.firstIndex(of: "=") else { return nil }
                let name = trimmed[..<equals].trimmingCharacters(in: .whitespaces)
                return name.hasPrefix("export ") ? String(name.dropFirst(7)) : name
            }
        )
    }

    /// Adds or replaces `NAME=value`, keeping the rest of the file intact.
    func set(_ name: String, to value: String) throws {
        let existing = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        var lines = existing.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.last == "" { lines.removeLast() }

        let assignment = "\(name)=\(value)"
        if let index = lines.firstIndex(where: { Self.variableName(of: $0) == name }) {
            lines[index] = assignment
        } else {
            lines.append(assignment)
        }

        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (lines.joined(separator: "\n") + "\n").write(to: fileURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    func remove(_ name: String) throws {
        guard let existing = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        let kept = existing
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { Self.variableName(of: String($0)) != name }
        try kept.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private static func variableName(of line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasPrefix("#"), let equals = trimmed.firstIndex(of: "=") else { return nil }
        let name = trimmed[..<equals].trimmingCharacters(in: .whitespaces)
        return name.hasPrefix("export ") ? String(name.dropFirst(7)) : name
    }
}
