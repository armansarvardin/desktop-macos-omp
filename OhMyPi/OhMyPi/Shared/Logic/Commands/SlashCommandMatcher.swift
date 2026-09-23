//
//  SlashCommandMatcher.swift
//  OhMyPi
//
//  Created by Arman Sarvardin on 22/9/26.
//

import Foundation

/// One row in the slash command palette.
nonisolated struct SlashSuggestion: Identifiable, Hashable, Sendable {
    var id: String
    /// Text shown in the leading column, e.g. `/model` or `on`.
    var title: String
    var detail: String?
    var hint: String?
    var source: String?
    /// Draft text after accepting this suggestion.
    var completion: String
    /// `true` when the command still needs arguments after completion.
    var expectsInput: Bool
}

/// Matches the composer draft against the commands the runtime advertised.
nonisolated enum SlashCommandMatcher {
    static let limit = 40

    /// Returns `nil` when the draft is not a slash command being typed.
    static func suggestions(for draft: String, commands: [RpcSlashCommand]) -> [SlashSuggestion]? {
        guard draft.hasPrefix("/"), !draft.contains("\n") else { return nil }

        let body = draft.dropFirst()
        guard let space = body.firstIndex(of: " ") else {
            return commandSuggestions(query: String(body), commands: commands)
        }

        let name = String(body[..<space]).lowercased()
        let rest = body[body.index(after: space)...]
        guard
            !rest.contains(" "),
            let command = commands.first(where: { $0.name.lowercased() == name || ($0.aliases ?? []).map { $0.lowercased() }.contains(name) }),
            let subcommands = command.subcommands, !subcommands.isEmpty
        else {
            return nil
        }

        return subcommandSuggestions(query: String(rest), command: command, subcommands: subcommands)
    }

    // MARK: - Private

    private static func commandSuggestions(query: String, commands: [RpcSlashCommand]) -> [SlashSuggestion] {
        let needle = query.lowercased()

        let ranked = commands.compactMap { command -> (Int, RpcSlashCommand)? in
            let names = [command.name] + (command.aliases ?? [])
            let lowered = names.map { $0.lowercased() }

            if needle.isEmpty { return (2, command) }
            if lowered.contains(needle) { return (0, command) }
            if lowered.contains(where: { $0.hasPrefix(needle) }) { return (1, command) }
            if lowered.contains(where: { $0.contains(needle) }) { return (2, command) }
            if needle.count >= 3, command.description?.lowercased().contains(needle) == true { return (3, command) }
            return nil
        }

        return ranked
            .sorted { lhs, rhs in
                let left = (lhs.0, sourceRank(lhs.1), lhs.1.name)
                let right = (rhs.0, sourceRank(rhs.1), rhs.1.name)
                return left < right
            }
            .prefix(limit)
            .map { _, command in
                let expectsInput = command.input?.hint != nil || !(command.subcommands ?? []).isEmpty
                return SlashSuggestion(
                    id: "command-\(command.name)",
                    title: "/\(command.name)",
                    detail: command.description,
                    hint: command.input?.hint,
                    source: command.source,
                    completion: expectsInput ? "/\(command.name) " : "/\(command.name)",
                    expectsInput: expectsInput
                )
            }
    }

    private static func subcommandSuggestions(
        query: String,
        command: RpcSlashCommand,
        subcommands: [RpcSlashCommand.Subcommand]
    ) -> [SlashSuggestion] {
        let needle = query.lowercased()

        return subcommands
            .filter { needle.isEmpty || $0.name.lowercased().hasPrefix(needle) }
            .prefix(limit)
            .map { subcommand in
                SlashSuggestion(
                    id: "subcommand-\(command.name)-\(subcommand.name)",
                    title: subcommand.name,
                    detail: subcommand.description,
                    hint: subcommand.usage,
                    source: nil,
                    completion: "/\(command.name) \(subcommand.name)",
                    expectsInput: false
                )
            }
    }

    /// Builtins first, then extensions and custom commands, skills last.
    private static func sourceRank(_ command: RpcSlashCommand) -> Int {
        switch command.source {
        case "builtin": 0
        case "extension", "custom", "file", "mcp_prompt": 1
        default: 2
        }
    }
}
