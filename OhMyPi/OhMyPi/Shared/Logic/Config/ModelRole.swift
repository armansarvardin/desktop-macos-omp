//
//  ModelRole.swift
//  OhMyPi
//
//  Created by Arman Sarvardin on 22/9/26.
//

import Foundation

/// A role value from `modelRoles`: `provider/modelId[:effort]` or `@otherRole`.
nonisolated enum ModelSelector: Hashable, Sendable {
    case model(qualifiedId: String, effort: String?)
    case role(String)
    case empty

    static let efforts = ["auto", "off", "minimal", "low", "medium", "high", "xhigh", "max"]

    nonisolated init(rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespaces)

        guard !trimmed.isEmpty else {
            self = .empty
            return
        }

        if trimmed.hasPrefix("@") {
            self = .role(String(trimmed.dropFirst()))
            return
        }

        if
            let colon = trimmed.lastIndex(of: ":"),
            Self.efforts.contains(String(trimmed[trimmed.index(after: colon)...]))
        {
            self = .model(qualifiedId: String(trimmed[..<colon]), effort: String(trimmed[trimmed.index(after: colon)...]))
        } else {
            self = .model(qualifiedId: trimmed, effort: nil)
        }
    }

    var rawValue: String {
        switch self {
        case .model(let qualifiedId, let effort):
            effort.map { "\(qualifiedId):\($0)" } ?? qualifiedId
        case .role(let role):
            "@\(role)"
        case .empty:
            ""
        }
    }

    var qualifiedId: String? {
        if case .model(let qualifiedId, _) = self { qualifiedId } else { nil }
    }

    var effort: String? {
        if case .model(_, let effort) = self { effort } else { nil }
    }

    func withEffort(_ effort: String?) -> ModelSelector {
        if case .model(let qualifiedId, _) = self {
            .model(qualifiedId: qualifiedId, effort: effort)
        } else {
            self
        }
    }
}

/// Display metadata from `modelTags`, layered over the CLI's built-in registry.
nonisolated struct ModelTag: Hashable, Sendable {
    static let colors = ["accent", "success", "warning", "error", "info", "muted", "dim"]

    var name: String
    var color: String?
    var hidden: Bool

    nonisolated init(name: String, color: String? = nil, hidden: Bool = false) {
        self.name = name
        self.color = color
        self.hidden = hidden
    }

    nonisolated init?(json: JSONValue) {
        guard let name = json["name"]?.stringValue else { return nil }
        self.name = name
        self.color = json["color"]?.stringValue
        self.hidden = json["hidden"]?.boolValue ?? false
    }

    /// Serialized with a stable key order (name, color, hidden).
    var json: String {
        var entries: [(String, JSONValue)] = [("name", .string(name))]
        if let color { entries.append(("color", .string(color))) }
        if hidden { entries.append(("hidden", .bool(true))) }
        return OmpConfigClient.orderedObject(entries)
    }
}

/// Follows `@role` references until a concrete model selector is reached.
nonisolated enum ModelRoleResolver {
    static func resolve(_ roleName: String, in roles: [ModelRole]) -> ModelSelector? {
        var visited: Set<String> = []
        var current = roleName
        var inheritedEffort: String?

        while visited.insert(current).inserted, let role = roles.first(where: { $0.name == current }) {
            switch role.selector {
            case .model(let qualifiedId, let effort):
                return .model(qualifiedId: qualifiedId, effort: inheritedEffort ?? effort)
            case .role(let target):
                // An explicit suffix on the referring role wins over the target's.
                inheritedEffort = inheritedEffort ?? role.selector.effort
                current = target
            case .empty:
                return nil
            }
        }

        return nil
    }

    /// Splits `provider/model-id` into the pair `set_model` expects.
    static func split(qualifiedId: String) -> (provider: String, modelId: String)? {
        guard let slash = qualifiedId.firstIndex(of: "/") else { return nil }
        return (String(qualifiedId[..<slash]), String(qualifiedId[qualifiedId.index(after: slash)...]))
    }
}

/// One editable row: a role with its assignment and tag.
nonisolated struct ModelRole: Identifiable, Hashable, Sendable {
    var name: String
    var selector: ModelSelector
    var tag: ModelTag?
    var isInCycle: Bool

    var id: String { name }

    var isBuiltIn: Bool {
        Self.builtIn[name] != nil
    }

    var displayName: String {
        tag?.name ?? Self.builtIn[name]?.name ?? name
    }

    var color: String {
        tag?.color ?? Self.builtIn[name]?.color ?? "muted"
    }

    var description: String? {
        Self.builtIn[name]?.description
    }

    struct BuiltIn: Sendable {
        var name: String
        var color: String
        var description: String
    }

    /// Mirrors `MODEL_ROLES` in `packages/coding-agent/src/config/model-roles.ts`.
    static let builtInOrder = ["default", "smol", "slow", "plan", "task", "advisor", "vision", "commit", "tiny", "memory", "judge", "web", "image", "speech", "dictation"]

    static let builtIn: [String: BuiltIn] = [
        "default": BuiltIn(name: "Default", color: "success", description: "Main chat model when no other role applies"),
        "smol": BuiltIn(name: "Fast", color: "warning", description: "Quick, cheap model for light turns and background helpers"),
        "slow": BuiltIn(name: "Thinking", color: "accent", description: "Strong model for hard reasoning"),
        "plan": BuiltIn(name: "Architect", color: "muted", description: "Planning and design passes"),
        "task": BuiltIn(name: "Subtask", color: "muted", description: "Delegated subagent tasks"),
        "advisor": BuiltIn(name: "Advisor", color: "accent", description: "Second-opinion advisor turns"),
        "vision": BuiltIn(name: "Vision", color: "error", description: "Image understanding fallback"),
        "commit": BuiltIn(name: "Commit", color: "dim", description: "Commit message generation"),
        "tiny": BuiltIn(name: "Tiny", color: "dim", description: "Session titles, memory and classification; falls back to Fast"),
        "memory": BuiltIn(name: "Memory", color: "dim", description: "Memory extraction and recall"),
        "judge": BuiltIn(name: "Judge", color: "muted", description: "Judgment API model for decisions"),
        "web": BuiltIn(name: "Web search", color: "success", description: "Web-grounded search model"),
        "image": BuiltIn(name: "Image generation", color: "accent", description: "Image generation model"),
        "speech": BuiltIn(name: "Speech", color: "warning", description: "Text to speech"),
        "dictation": BuiltIn(name: "Dictation", color: "warning", description: "Speech to text")
    ]
}
