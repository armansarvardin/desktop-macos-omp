//
//  TranscriptItem.swift
//  OhMyPi
//
//  Created by Arman Sarvardin on 22/9/26.
//

import Foundation

/// One row in the conversation transcript.
nonisolated struct TranscriptItem: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case user(UserContent)
        case assistant(AssistantContent)
        case notice(Notice)
        case compaction(String)
        case commandOutput(String)
    }

    let id: String
    var kind: Kind
    var timestamp: Date
}

// MARK: - User

nonisolated struct UserContent: Hashable, Sendable {
    var text: String
    var imageCount: Int
    var isSteering: Bool
    /// Added locally before the runtime echoed it back.
    var isPending: Bool
    /// A `/slash` command rather than a prompt for the model.
    var isCommand: Bool = false
}

// MARK: - Assistant

nonisolated struct AssistantContent: Hashable, Sendable {
    var blocks: [AssistantBlock]
    var model: String?
    var isStreaming: Bool
    var errorMessage: String?

    var hasVisibleContent: Bool {
        blocks.contains { block in
            switch block.kind {
            case .text(let text): !text.isEmpty
            case .thinking(let thinking): !thinking.isEmpty
            case .toolCall, .image: true
            }
        }
    }
}

nonisolated struct AssistantBlock: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case text(String)
        case thinking(String)
        case toolCall(ToolCallState)
        case image(mimeType: String)
    }

    let id: String
    var kind: Kind
}

nonisolated struct ToolCallState: Hashable, Sendable {
    enum Status: Hashable, Sendable {
        case pending
        case running
        case succeeded
        case failed
    }

    var id: String
    var name: String
    var arguments: JSONValue
    var status: Status
    var resultText: String
    var resultImageCount: Int
    var details: JSONValue?

    /// Short one-line summary of the call for card headers.
    var summary: String {
        let argument = arguments.objectValue ?? [:]

        switch name {
        case "bash":
            return argument["cmd"]?.stringValue ?? argument["command"]?.stringValue ?? ""
        case "read", "write", "edit", "glob", "grep":
            let path = argument["path"]?.stringValue ?? argument["file_path"]?.stringValue
            let pattern = argument["pattern"]?.stringValue
            return [pattern, path].compactMap { $0 }.joined(separator: " in ")
        case "task":
            return argument["description"]?.stringValue ?? argument["prompt"]?.stringValue ?? ""
        case "web_search":
            return argument["query"]?.stringValue ?? ""
        default:
            if let firstString = argument.values.compactMap(\.stringValue).first {
                return firstString
            }
            return argument.isEmpty ? "" : arguments.prettyPrinted
        }
    }
}

// MARK: - Notice

nonisolated struct Notice: Hashable, Sendable {
    enum Level: String, Hashable, Sendable {
        case info
        case warning
        case error
    }

    var level: Level
    var message: String
    var source: String?
}
