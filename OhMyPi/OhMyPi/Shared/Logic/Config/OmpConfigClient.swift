//
//  OmpConfigClient.swift
//  OhMyPi
//
//  Created by Arman Sarvardin on 22/9/26.
//

import Foundation

/// Reads and writes `~/.omp/agent/config.yml` through `omp config`, so the
/// CLI keeps ownership of parsing, validation and backups.
/// A config value plus the key order the file had, which dictionaries lose.
nonisolated struct ConfigValue: Sendable {
    var value: JSONValue
    var keyOrder: [String]

    nonisolated init(value: JSONValue, keyOrder: [String] = []) {
        self.value = value
        self.keyOrder = keyOrder
    }
}

nonisolated struct OmpConfigClient: Sendable {
    let get: @Sendable (_ key: String) async throws -> ConfigValue
    /// Writes a pre-serialized JSON value so key order in the YAML is preserved.
    let set: @Sendable (_ key: String, _ json: String) async throws -> Void

    static func live(settings: @escaping @Sendable () -> LaunchSettings = { LaunchSettings.current() }) -> OmpConfigClient {
        OmpConfigClient(
            get: { key in
                let launch = settings()
                let output = try await ShellCommand.run(
                    executable: launch.executable,
                    arguments: ["config", "get", key, "--json"],
                    useLoginShell: launch.useLoginShell
                )
                guard output.succeeded else {
                    throw ShellCommand.Failure.nonZeroExit(output.exitCode, output.stderr)
                }
                return try Self.parseGetOutput(output.stdout)
            },
            set: { key, json in
                let launch = settings()
                let output = try await ShellCommand.run(
                    executable: launch.executable,
                    arguments: ["config", "set", key, json],
                    useLoginShell: launch.useLoginShell
                )
                guard output.succeeded else {
                    throw ShellCommand.Failure.nonZeroExit(output.exitCode, output.stderr)
                }
            }
        )
    }

    static let `default` = OmpConfigClient.live()

    // MARK: - Serialization

    /// JSON object with keys in the given order.
    static func orderedObject(_ entries: [(String, JSONValue)]) -> String {
        "{" + entries.map { key, value in "\(encode(.string(key))):\(encode(value))" }.joined(separator: ",") + "}"
    }

    static func array(_ values: [JSONValue]) -> String {
        "[" + values.map(encode).joined(separator: ",") + "]"
    }

    static func encode(_ value: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
        return (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? "null"
    }

    /// `omp config get --json` prints `{ key, value, type }`; login shells may
    /// prepend banner text, so the JSON object is located by its first brace.
    private static func parseGetOutput(_ stdout: String) throws -> ConfigValue {
        guard
            let start = stdout.firstIndex(of: "{"),
            let data = String(stdout[start...]).data(using: .utf8)
        else {
            throw RpcError.malformedFrame("config output was not JSON")
        }

        let payload = try JSONDecoder().decode(JSONValue.self, from: data)
        let json = String(stdout[start...])
        return ConfigValue(value: payload["value"] ?? .null, keyOrder: topLevelKeys(ofValueIn: json))
    }

    /// Keys of the `"value"` object in the order they appear in the JSON text.
    static func topLevelKeys(ofValueIn json: String) -> [String] {
        guard let valueRange = json.range(of: "\"value\"") else { return [] }
        var index = valueRange.upperBound
        while index < json.endIndex, json[index] != "{" {
            if json[index] == "[" || json[index] == "\"" { return [] }
            index = json.index(after: index)
        }
        guard index < json.endIndex else { return [] }

        var keys: [String] = []
        var depth = 0
        var inString = false
        var escaped = false
        var current = ""
        var lastString: String?

        for character in json[index...] {
            if inString {
                if escaped {
                    current.append(character)
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                    lastString = current
                } else {
                    current.append(character)
                }
                continue
            }

            switch character {
            case "\"":
                inString = true
                current = ""
            case "{", "[":
                depth += 1
            case "}", "]":
                depth -= 1
                if depth == 0 { return keys }
            case ":":
                if depth == 1, let key = lastString {
                    keys.append(key)
                    lastString = nil
                }
            default:
                break
            }
        }

        return keys
    }
}
