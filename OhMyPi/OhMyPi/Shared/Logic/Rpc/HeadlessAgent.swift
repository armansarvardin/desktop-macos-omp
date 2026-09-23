//
//  HeadlessAgent.swift
//  OhMyPi
//
//  Created by Arman Sarvardin on 23/9/26.
//

import Foundation

/// A throwaway `omp --mode rpc --no-session` process for queries that need the
/// runtime but no conversation: model catalog, login providers, OAuth logins.
@MainActor
final class HeadlessAgent {
    let client: RpcClient

    private init(client: RpcClient) {
        self.client = client
    }

    /// Spawns the agent and completes the protocol handshake.
    static func start(
        launcher: RpcLauncher,
        settings: LaunchSettings = .current(),
        onEvent: @escaping (JSONValue) -> Void = { _ in }
    ) async throws -> HeadlessAgent {
        let transport = try launcher.launch(settings.headlessRpcConfiguration())
        let client = RpcClient(transport: transport)
        client.onEvent = onEvent

        try await client.waitUntilReady()
        try await client.request(.negotiateProtocol(version: 2))
        return HeadlessAgent(client: client)
    }

    func loginProviders() async throws -> [RpcLoginProvider] {
        let payload = try await client.request(.getLoginProviders)
        return try payload?["providers"]?.decoded(as: [RpcLoginProvider].self) ?? []
    }

    func availableModels() async throws -> [RpcModel] {
        let payload = try await client.request(.getAvailableModels)
        return try payload?["models"]?.decoded(as: [RpcModel].self) ?? []
    }

    func stop() {
        client.shutdown()
    }
}
