//
//  RpcModels.swift
//  OhMyPi
//
//  Created by Arman Sarvardin on 22/9/26.
//

import Foundation

// MARK: - Session state

/// Payload of the `get_state` response.
nonisolated struct RpcSessionState: Decodable, Sendable {
    var model: RpcModel?
    var thinkingLevel: String?
    var isStreaming: Bool
    var isCompacting: Bool
    var sessionFile: String?
    var sessionId: String
    var sessionName: String?
    var autoCompactionEnabled: Bool
    var fastModeEnabled: Bool
    var fastModeActive: Bool
    var tokensPerSecond: Double?
    var messageCount: Int
    var queuedMessageCount: Int
    var contextUsage: RpcContextUsage?
}

nonisolated struct RpcContextUsage: Decodable, Sendable, Equatable {
    var tokens: Int
    var contextWindow: Int
    var percent: Double
}

// MARK: - Model catalog

/// Narrowed view of the catalog `Model` record, enough for a picker and a status bar.
nonisolated struct RpcModel: Decodable, Sendable, Hashable, Identifiable {
    /// RPC sends `{ mode, efforts, defaultLevel }`; `omp models --json` sends the efforts array only.
    struct Thinking: Decodable, Sendable, Hashable {
        var mode: String?
        var efforts: [String]?
        var defaultLevel: String?

        private enum CodingKeys: String, CodingKey {
            case mode, efforts, defaultLevel
        }

        nonisolated init(from decoder: Decoder) throws {
            if let efforts = try? decoder.singleValueContainer().decode([String].self) {
                self.efforts = efforts
                return
            }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            mode = try container.decodeIfPresent(String.self, forKey: .mode)
            efforts = try container.decodeIfPresent([String].self, forKey: .efforts)
            defaultLevel = try container.decodeIfPresent(String.self, forKey: .defaultLevel)
        }
    }

    struct Cost: Decodable, Sendable, Hashable {
        var input: Double?
        var output: Double?
    }

    var id: String
    var name: String
    var provider: String
    var api: String?
    var reasoning: Bool?
    var input: [String]?
    var contextWindow: Int?
    var maxTokens: Int?
    var thinking: Thinking?
    var cost: Cost?

    /// Stable identity across providers exposing the same model id.
    var qualifiedId: String {
        "\(provider)/\(id)"
    }

    var supportsImages: Bool {
        input?.contains("image") ?? false
    }
}

nonisolated enum ThinkingLevel: String, CaseIterable, Sendable, Identifiable {
    case off
    case minimal
    case low
    case medium
    case high
    case xhigh
    case max

    var id: String { rawValue }

    var title: String {
        switch self {
        case .xhigh: "Extra high"
        default: rawValue.capitalized
        }
    }
}

// MARK: - Slash commands

nonisolated struct RpcSlashCommand: Decodable, Sendable, Hashable, Identifiable {
    struct Input: Decodable, Sendable, Hashable {
        var hint: String?
    }

    struct Subcommand: Decodable, Sendable, Hashable {
        var name: String
        var description: String?
        var usage: String?
    }

    var name: String
    var aliases: [String]?
    var description: String?
    var input: Input?
    var subcommands: [Subcommand]?
    var source: String?

    var id: String { name }
}

// MARK: - Messages

nonisolated struct RpcMessagesPage: Decodable, Sendable {
    var messages: [AgentMessage]
    var nextCursor: String?
    var totalMessages: Int
}

/// One block inside an assistant message or a tool result.
nonisolated enum MessageContent: Sendable, Hashable {
    case text(String)
    case thinking(String)
    case toolCall(id: String, name: String, arguments: JSONValue)
    case image(mimeType: String)
    case other(type: String)
}

extension MessageContent: Decodable {
    private enum CodingKeys: String, CodingKey {
        case type, text, thinking, id, name, arguments, mimeType
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "text":
            self = .text(try container.decodeIfPresent(String.self, forKey: .text) ?? "")
        case "thinking":
            self = .thinking(try container.decodeIfPresent(String.self, forKey: .thinking) ?? "")
        case "toolCall":
            self = .toolCall(
                id: try container.decode(String.self, forKey: .id),
                name: try container.decode(String.self, forKey: .name),
                arguments: try container.decodeIfPresent(JSONValue.self, forKey: .arguments) ?? .object([:])
            )
        case "image":
            self = .image(mimeType: try container.decodeIfPresent(String.self, forKey: .mimeType) ?? "image")
        default:
            self = .other(type: type)
        }
    }
}

/// Discriminated `AgentMessage` union keyed by `role`.
nonisolated enum AgentMessage: Sendable {
    struct User: Sendable {
        var content: [MessageContent]
        var timestamp: Double?
        var synthetic: Bool
        var steering: Bool
    }

    struct Assistant: Sendable {
        var content: [MessageContent]
        var model: String?
        var provider: String?
        var stopReason: String?
        var errorMessage: String?
        var timestamp: Double?
    }

    struct ToolResult: Sendable {
        var toolCallId: String
        var toolName: String
        var content: [MessageContent]
        var details: JSONValue?
        var isError: Bool
        var timestamp: Double?
    }

    case user(User)
    case assistant(Assistant)
    case toolResult(ToolResult)
    case other(role: String, payload: JSONValue)
}

extension AgentMessage: Decodable {
    private enum CodingKeys: String, CodingKey {
        case role, content, timestamp, synthetic, steering
        case model, provider, stopReason, errorMessage
        case toolCallId, toolName, details, isError
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let role = try container.decode(String.self, forKey: .role)

        switch role {
        case "user":
            self = .user(
                User(
                    content: try Self.decodeContent(from: container),
                    timestamp: try container.decodeIfPresent(Double.self, forKey: .timestamp),
                    synthetic: try container.decodeIfPresent(Bool.self, forKey: .synthetic) ?? false,
                    steering: try container.decodeIfPresent(Bool.self, forKey: .steering) ?? false
                )
            )
        case "assistant":
            self = .assistant(
                Assistant(
                    content: try Self.decodeContent(from: container),
                    model: try container.decodeIfPresent(String.self, forKey: .model),
                    provider: try container.decodeIfPresent(String.self, forKey: .provider),
                    stopReason: try container.decodeIfPresent(String.self, forKey: .stopReason),
                    errorMessage: try container.decodeIfPresent(String.self, forKey: .errorMessage),
                    timestamp: try container.decodeIfPresent(Double.self, forKey: .timestamp)
                )
            )
        case "toolResult":
            self = .toolResult(
                ToolResult(
                    toolCallId: try container.decode(String.self, forKey: .toolCallId),
                    toolName: try container.decodeIfPresent(String.self, forKey: .toolName) ?? "",
                    content: try Self.decodeContent(from: container),
                    details: try container.decodeIfPresent(JSONValue.self, forKey: .details),
                    isError: try container.decodeIfPresent(Bool.self, forKey: .isError) ?? false,
                    timestamp: try container.decodeIfPresent(Double.self, forKey: .timestamp)
                )
            )
        default:
            let payload = try JSONValue(from: decoder)
            self = .other(role: role, payload: payload)
        }
    }

    /// `content` is either a plain string (user messages) or an array of blocks.
    nonisolated private static func decodeContent(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> [MessageContent] {
        if let string = try? container.decode(String.self, forKey: .content) {
            return [.text(string)]
        }

        return try container.decodeIfPresent([MessageContent].self, forKey: .content) ?? []
    }
}

extension [MessageContent] {
    /// Concatenated text blocks, used for previews and tool result bodies.
    nonisolated var joinedText: String {
        compactMap { block in
            if case .text(let text) = block { text } else { nil }
        }
        .joined(separator: "\n")
    }
}

// MARK: - Tool results

nonisolated struct AgentToolResult: Decodable, Sendable {
    var content: [MessageContent]
    var details: JSONValue?
    var isError: Bool?

    nonisolated init(content: [MessageContent], details: JSONValue? = nil, isError: Bool? = nil) {
        self.content = content
        self.details = details
        self.isError = isError
    }

    private enum CodingKeys: String, CodingKey {
        case content, details, isError
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let string = try? container.decode(String.self, forKey: .content) {
            content = [.text(string)]
        } else {
            content = try container.decodeIfPresent([MessageContent].self, forKey: .content) ?? []
        }

        details = try container.decodeIfPresent(JSONValue.self, forKey: .details)
        isError = try container.decodeIfPresent(Bool.self, forKey: .isError)
    }
}

// MARK: - Extension UI

/// A UI request emitted by the agent runtime (tool approvals, `ask` tool, logins).
nonisolated struct ExtensionUIRequest: Sendable, Identifiable, Hashable {
    enum Method: Sendable, Hashable {
        case select(title: String, options: [String], details: [String?])
        case confirm(title: String, message: String)
        case input(title: String, placeholder: String?)
        case editor(title: String, prefill: String?)
        case openURL(url: String, instructions: String?)
        case notify(message: String, level: String)
        case setStatus(key: String, text: String?)
        case setWidget(key: String, lines: [String]?)
        case setTitle(String)
        case setEditorText(String)
        case cancel(targetId: String)
        case unknown(String)
    }

    var id: String
    var method: Method
    var timeout: Double?

    /// Requests the runtime waits on; everything else is fire-and-forget.
    var expectsResponse: Bool {
        switch method {
        case .select, .confirm, .input, .editor:
            true
        default:
            false
        }
    }

    nonisolated init?(frame: JSONValue) {
        guard
            let id = frame["id"]?.stringValue,
            let method = frame["method"]?.stringValue
        else {
            return nil
        }

        self.id = id
        self.timeout = frame["timeout"]?.doubleValue

        let title = frame["title"]?.stringValue ?? ""

        switch method {
        case "select":
            let options = frame["options"]?.arrayValue?.compactMap(\.stringValue) ?? []
            let details = frame["optionDetails"]?.arrayValue?.map { $0["description"]?.stringValue } ?? []
            self.method = .select(title: title, options: options, details: details)
        case "confirm":
            self.method = .confirm(title: title, message: frame["message"]?.stringValue ?? "")
        case "input":
            self.method = .input(title: title, placeholder: frame["placeholder"]?.stringValue)
        case "editor":
            self.method = .editor(title: title, prefill: frame["prefill"]?.stringValue)
        case "open_url":
            self.method = .openURL(
                url: frame["url"]?.stringValue ?? "",
                instructions: frame["instructions"]?.stringValue
            )
        case "notify":
            self.method = .notify(
                message: frame["message"]?.stringValue ?? "",
                level: frame["notifyType"]?.stringValue ?? "info"
            )
        case "setStatus":
            self.method = .setStatus(
                key: frame["statusKey"]?.stringValue ?? "",
                text: frame["statusText"]?.stringValue
            )
        case "setWidget":
            self.method = .setWidget(
                key: frame["widgetKey"]?.stringValue ?? "",
                lines: frame["widgetLines"]?.arrayValue?.compactMap(\.stringValue)
            )
        case "setTitle":
            self.method = .setTitle(title)
        case "set_editor_text":
            self.method = .setEditorText(frame["text"]?.stringValue ?? "")
        case "cancel":
            self.method = .cancel(targetId: frame["targetId"]?.stringValue ?? "")
        default:
            self.method = .unknown(method)
        }
    }
}

// MARK: - Errors

nonisolated enum RpcError: LocalizedError, Sendable {
    case commandFailed(command: String, message: String, code: String?)
    case processExited(code: Int32)
    case transportClosed
    case executableNotFound(String)
    case malformedFrame(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let command, let message, _):
            "\(command): \(message)"
        case .processExited(let code):
            "oh-my-pi exited with code \(code)"
        case .transportClosed:
            "Connection to oh-my-pi was closed"
        case .executableNotFound(let path):
            "oh-my-pi executable not found at \(path)"
        case .malformedFrame(let reason):
            "Malformed RPC frame: \(reason)"
        }
    }
}
