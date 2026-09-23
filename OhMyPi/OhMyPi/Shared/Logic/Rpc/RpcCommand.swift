//
//  RpcCommand.swift
//  OhMyPi
//
//  Created by Arman Sarvardin on 22/9/26.
//

import Foundation

/// Outgoing stdin commands, mirroring `RpcCommand` in `rpc-types.ts`.
nonisolated enum RpcCommand: Sendable {
    case negotiateProtocol(version: Int)
    case prompt(message: String, streamingBehavior: String?)
    case steer(message: String)
    case followUp(message: String)
    case abort
    case newSession
    case getState
    case getAvailableCommands
    case setModel(provider: String, modelId: String)
    case cycleModel
    case getAvailableModels
    case setThinkingLevel(String)
    case setFastMode(Bool)
    case compact(customInstructions: String?)
    case setAutoCompaction(Bool)
    case getSessionStats
    case switchSession(path: String)
    case setSessionName(String)
    case getMessagesPage(cursor: String?, limit: Int)
    case getLoginProviders
    case login(providerId: String)
    case exportHTML(outputPath: String?)
    case handoff(customInstructions: String?)

    /// Wire name used to label responses.
    var name: String {
        switch self {
        case .negotiateProtocol: "negotiate_protocol"
        case .prompt: "prompt"
        case .steer: "steer"
        case .followUp: "follow_up"
        case .abort: "abort"
        case .newSession: "new_session"
        case .getState: "get_state"
        case .getAvailableCommands: "get_available_commands"
        case .setModel: "set_model"
        case .cycleModel: "cycle_model"
        case .getAvailableModels: "get_available_models"
        case .setThinkingLevel: "set_thinking_level"
        case .setFastMode: "set_fast_mode"
        case .compact: "compact"
        case .setAutoCompaction: "set_auto_compaction"
        case .getSessionStats: "get_session_stats"
        case .switchSession: "switch_session"
        case .setSessionName: "set_session_name"
        case .getMessagesPage: "get_messages_page"
        case .getLoginProviders: "get_login_providers"
        case .login: "login"
        case .exportHTML: "export_html"
        case .handoff: "handoff"
        }
    }

    /// Full JSON body including the correlation id.
    func payload(id: String) -> JSONValue {
        var object: [String: JSONValue] = [
            "id": .string(id),
            "type": .string(name)
        ]

        switch self {
        case .negotiateProtocol(let version):
            object["protocolVersion"] = .number(Double(version))
        case .prompt(let message, let streamingBehavior):
            object["message"] = .string(message)
            if let streamingBehavior {
                object["streamingBehavior"] = .string(streamingBehavior)
            }
        case .steer(let message), .followUp(let message):
            object["message"] = .string(message)
        case .setModel(let provider, let modelId):
            object["provider"] = .string(provider)
            object["modelId"] = .string(modelId)
        case .setThinkingLevel(let level):
            object["level"] = .string(level)
        case .setFastMode(let enabled), .setAutoCompaction(let enabled):
            object["enabled"] = .bool(enabled)
        case .compact(let customInstructions), .handoff(let customInstructions):
            if let customInstructions {
                object["customInstructions"] = .string(customInstructions)
            }
        case .switchSession(let path):
            object["sessionPath"] = .string(path)
        case .setSessionName(let name):
            object["name"] = .string(name)
        case .getMessagesPage(let cursor, let limit):
            if let cursor {
                object["cursor"] = .string(cursor)
            }
            object["limit"] = .number(Double(limit))
        case .login(let providerId):
            object["providerId"] = .string(providerId)
        case .exportHTML(let outputPath):
            if let outputPath {
                object["outputPath"] = .string(outputPath)
            }
        case .abort, .newSession, .getState, .getAvailableCommands, .cycleModel,
             .getAvailableModels, .getSessionStats, .getLoginProviders:
            break
        }

        return .object(object)
    }
}

/// Replies to `extension_ui_request` frames.
nonisolated enum ExtensionUIResponse: Sendable {
    case value(String)
    case confirmed(Bool)
    case cancelled

    func payload(id: String) -> JSONValue {
        var object: [String: JSONValue] = [
            "id": .string(id),
            "type": "extension_ui_response"
        ]

        switch self {
        case .value(let value):
            object["value"] = .string(value)
        case .confirmed(let confirmed):
            object["confirmed"] = .bool(confirmed)
        case .cancelled:
            object["cancelled"] = .bool(true)
        }

        return .object(object)
    }
}
