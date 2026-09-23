//
//  SessionPaths.swift
//  OhMyPi
//
//  Created by Arman Sarvardin on 22/9/26.
//

import Foundation

/// Mirrors `session-paths.ts` so the app finds the CLI's own session folders.
nonisolated enum SessionPaths {
    /// `~/.omp/agent` unless `PI_CODING_AGENT_DIR` relocates it.
    static var agentRoot: URL {
        if let override = ProcessInfo.processInfo.environment["PI_CODING_AGENT_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".omp/agent", directoryHint: .isDirectory)
    }

    static var defaultSessionsRoot: URL {
        agentRoot.appending(path: "sessions", directoryHint: .isDirectory)
    }

    /// Folder name the CLI uses for a working directory.
    ///
    /// - Under `$HOME`: `-<relative path with / replaced by ->`
    /// - Under the temp root: `-tmp-<relative>`
    /// - Elsewhere: `--<absolute path without leading slash>--`
    static func encodedDirectoryName(for cwd: URL) -> String {
        let canonical = canonicalPath(cwd.path)
        let home = canonicalPath(FileManager.default.homeDirectoryForCurrentUser.path)
        let temp = canonicalPath(NSTemporaryDirectory())

        if let relative = relativePath(of: canonical, under: home) {
            return encodeRelative(prefix: "-", relative: relative)
        }
        if let relative = relativePath(of: canonical, under: temp) {
            return encodeRelative(prefix: "-tmp", relative: relative)
        }

        let stripped = canonical.hasPrefix("/") ? String(canonical.dropFirst()) : canonical
        return "--\(stripped.replacing("/", with: "-"))--"
    }

    // MARK: - Private

    /// Uses `realpath(3)` rather than Foundation, which strips the `/private`
    /// prefix and would encode `/tmp` differently from the CLI.
    private static func canonicalPath(_ path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        var resolved = expanded

        if let pointer = realpath(expanded, nil) {
            resolved = String(cString: pointer)
            free(pointer)
        }

        return resolved.count > 1 && resolved.hasSuffix("/") ? String(resolved.dropLast()) : resolved
    }

    private static func relativePath(of path: String, under root: String) -> String? {
        if path == root { return "" }
        guard path.hasPrefix(root + "/") else { return nil }
        return String(path.dropFirst(root.count + 1))
    }

    private static func encodeRelative(prefix: String, relative: String) -> String {
        let encoded = relative.replacing("/", with: "-").replacing(":", with: "-")
        guard !encoded.isEmpty else { return prefix }
        return prefix.hasSuffix("-") ? prefix + encoded : "\(prefix)-\(encoded)"
    }
}
