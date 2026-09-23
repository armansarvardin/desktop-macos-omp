//
//  PreviewEnvironment.swift
//  OhMyPi
//
//  Created by Arman Sarvardin on 22/9/26.
//

import Foundation
import SwiftUI

/// Transport that replays canned frames instead of spawning a process.
nonisolated final class MockRpcTransport: RpcTransport, @unchecked Sendable {
    let frames: AsyncStream<JSONValue>
    private(set) var exitCode: Int32?
    private let continuation: AsyncStream<JSONValue>.Continuation
    private var requestCounter = 0

    init(scripted: [JSONValue] = MockRpcTransport.welcomeScript) {
        var continuation: AsyncStream<JSONValue>.Continuation!
        frames = AsyncStream { continuation = $0 }
        self.continuation = continuation

        continuation.yield(["type": "ready", "protocolVersion": 1, "supportedProtocolVersions": [1, 2]])
        scripted.forEach { continuation.yield($0) }
    }

    func send(_ frame: JSONValue) throws {
        guard let id = frame["id"]?.stringValue, let type = frame["type"]?.stringValue else { return }

        let data: JSONValue = switch type {
        case "negotiate_protocol": ["protocolVersion": 2]
        case "get_state": Self.sampleState
        case "get_available_models": ["models": [Self.sampleModel, Self.secondModel]]
        case "get_messages_page": ["messages": [], "totalMessages": 0]
        case "get_login_providers": ["providers": [
            ["id": "anthropic", "name": "Anthropic (Claude Pro/Max)", "available": true, "authenticated": true],
            ["id": "openai", "name": "OpenAI", "available": true, "authenticated": false],
            ["id": "openrouter", "name": "OpenRouter", "available": true, "authenticated": false]
        ]]
        case "login": ["providerId": "anthropic"]
        default: .null
        }

        continuation.yield(["id": .string(id), "type": "response", "command": .string(type), "success": true, "data": data])

        if type == "prompt", let message = frame["message"]?.stringValue {
            Self.echoScript(for: message).forEach { continuation.yield($0) }
        }
    }

    func closeInput() {}

    func terminate() {
        exitCode = 0
        continuation.finish()
    }

    // MARK: - Fixtures

    static let sampleModel: JSONValue = [
        "id": "claude-fable-5-1", "name": "Claude Fable 5.1", "provider": "anthropic",
        "reasoning": true, "input": ["text", "image"], "contextWindow": 1_000_000,
        "thinking": ["mode": "effort", "efforts": ["low", "medium", "high"]]
    ]

    static let secondModel: JSONValue = [
        "id": "gpt-5.5", "name": "GPT-5.5", "provider": "openai",
        "reasoning": true, "input": ["text"], "contextWindow": 400_000
    ]

    static let sampleState: JSONValue = [
        "model": sampleModel, "thinkingLevel": "high", "isStreaming": false, "isCompacting": false,
        "steeringMode": "one-at-a-time", "followUpMode": "one-at-a-time", "interruptMode": "immediate",
        "sessionId": "preview", "autoCompactionEnabled": true, "fastModeEnabled": false, "fastModeActive": false,
        "tokensPerSecond": 42.5, "messageCount": 3, "queuedMessageCount": 0, "todoPhases": [],
        "contextUsage": ["tokens": 24_500, "contextWindow": 1_000_000, "percent": 2.45]
    ]

    static let welcomeScript: [JSONValue] = [
        ["type": "message_start", "message": ["role": "user", "content": "Explain what this repository does", "timestamp": 1_790_000_000_000]],
        ["type": "message_end", "message": ["role": "user", "content": "Explain what this repository does", "timestamp": 1_790_000_000_000]],
        ["type": "message_start", "message": ["role": "assistant", "content": [], "model": "claude-fable-5-1"]],
        ["type": "message_end", "message": [
            "role": "assistant", "model": "claude-fable-5-1",
            "content": [
                ["type": "thinking", "thinking": "I should look at the README first."],
                ["type": "toolCall", "id": "call_1", "name": "read", "arguments": ["path": "README.md"]],
                ["type": "text", "text": "This is **oh-my-pi**, a coding agent.\n\n- It runs in the terminal\n- It speaks an RPC protocol\n\n```swift\nlet answer = 42\n```"]
            ]
        ]],
        ["type": "tool_execution_start", "toolCallId": "call_1", "toolName": "read", "args": ["path": "README.md"]],
        ["type": "tool_execution_end", "toolCallId": "call_1", "toolName": "read", "result": ["content": [["type": "text", "text": "# oh-my-pi\nA coding agent."]]]],
        ["type": "agent_end", "messages": []]
    ]

    static func echoScript(for message: String) -> [JSONValue] {
        [
            ["type": "agent_start"],
            ["type": "message_start", "message": ["role": "user", "content": .string(message)]],
            ["type": "message_start", "message": ["role": "assistant", "content": []]],
            ["type": "message_update", "message": ["role": "assistant", "content": []],
             "assistantMessageEvent": ["type": "text_delta", "contentIndex": 0, "delta": .string("You said: \(message)")]],
            ["type": "message_end", "message": ["role": "assistant", "content": [["type": "text", "text": .string("You said: \(message)")]]]],
            ["type": "agent_end", "messages": []]
        ]
    }
}

extension RpcLauncher {
    static let mock = RpcLauncher { _ in MockRpcTransport() }
}

extension ModelCatalogService {
    static let mock = ModelCatalogService(
        models: {
            [
                try MockRpcTransport.sampleModel.decoded(as: RpcModel.self),
                try MockRpcTransport.secondModel.decoded(as: RpcModel.self)
            ]
        },
        refresh: {}
    )
}

extension OmpConfigClient {
    static let mock = OmpConfigClient(
        get: { key in
            switch key {
            case "disabledProviders": ConfigValue(value: ["openrouter"])
            case "enabledModels": ConfigValue(value: [])
            case "modelRoles":
                ConfigValue(
                    value: ["default": "anthropic/claude-fable-5-1", "smol": "openai/gpt-5.5:low", "azure": "openai/gpt-5.5"],
                    keyOrder: ["smol", "default", "azure"]
                )
            case "modelTags": ConfigValue(value: ["azure": ["name": "Azure GPT", "color": "accent"]], keyOrder: ["azure"])
            case "cycleOrder": ConfigValue(value: ["smol", "default", "azure"])
            default: ConfigValue(value: .null)
            }
        },
        set: { _, _ in }
    )

}

// MARK: - Preview environment

struct PreviewEnvironmentModifier: ViewModifier {
    @State private var workspaceStateModel: WorkspaceStateModel = {
        let model = WorkspaceStateModel(
            sessionStore: SessionStore(sessionsRoot: URL(fileURLWithPath: "/nonexistent")),
            launcher: .mock,
            configClient: .mock,
            defaults: UserDefaults(suiteName: "sh.omp.desktop.preview") ?? .standard
        )
        model.newSession(in: URL(fileURLWithPath: "/Users/preview/Projects/oh-my-pi"))
        return model
    }()

    func body(content: Content) -> some View {
        content
            .environment(workspaceStateModel)
            .environment(\.rpcLauncher, .mock)
            .environment(\.ompConfigClient, .mock)
            .environment(\.modelCatalogService, .mock)
    }
}

extension View {
    func withPreviewEnvironment() -> some View {
        modifier(PreviewEnvironmentModifier())
    }
}

extension AgentSessionStateModel {
    /// A session backed by the mock transport, already started.
    static var preview: AgentSessionStateModel {
        let session = AgentSessionStateModel(
            projectURL: URL(fileURLWithPath: "/Users/preview/Projects/oh-my-pi"),
            launcher: .mock,
            launchConfiguration: RpcLaunchConfiguration(
                executable: "omp",
                arguments: [],
                workingDirectory: URL(fileURLWithPath: "/Users/preview/Projects/oh-my-pi")
            )
        )
        Task { await session.start() }
        return session
    }
}
