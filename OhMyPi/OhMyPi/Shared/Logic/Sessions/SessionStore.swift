//
//  SessionStore.swift
//  OhMyPi
//
//  Created by Arman Sarvardin on 22/9/26.
//

import Foundation

/// A session file found under `~/.omp/agent/sessions`.
nonisolated struct StoredSession: Identifiable, Hashable, Sendable {
    var id: String
    var fileURL: URL
    var projectURL: URL
    var title: String
    var preview: String
    var createdAt: Date
    var modifiedAt: Date

    var displayTitle: String {
        if !title.isEmpty { return title }
        if !preview.isEmpty { return preview }
        return "Untitled session"
    }
}

/// Reads the on-disk JSONL session store the CLI maintains.
///
/// The RPC protocol exposes no session listing, so the app scans the same
/// directory layout the CLI uses: one folder per encoded working directory.
nonisolated struct SessionStore: Sendable {
    var sessionsRoot: URL = SessionPaths.defaultSessionsRoot

    /// Sessions for a project, newest first.
    func sessions(for projectURL: URL) -> [StoredSession] {
        let directory = sessionsRoot.appending(path: SessionPaths.encodedDirectoryName(for: projectURL))
        return sessions(inDirectory: directory, projectURL: projectURL)
    }

    /// Every project that has at least one stored session, newest first.
    func knownProjects() -> [URL] {
        guard
            let directories = try? FileManager.default.contentsOfDirectory(
                at: sessionsRoot,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return []
        }

        let projects = directories.compactMap { directory -> (URL, Date)? in
            guard
                let newest = newestSessionFile(in: directory),
                let header = readHeader(of: newest),
                let cwd = header.cwd
            else {
                return nil
            }
            let modified = (try? newest.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return (URL(fileURLWithPath: cwd, isDirectory: true), modified)
        }

        return projects
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    // MARK: - Private

    private func sessions(inDirectory directory: URL, projectURL: URL) -> [StoredSession] {
        guard
            let files = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return []
        }

        return files
            .filter { $0.pathExtension == "jsonl" }
            .compactMap { file in readSession(at: file, projectURL: projectURL) }
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    private func newestSessionFile(in directory: URL) -> URL? {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return files
            .filter { $0.pathExtension == "jsonl" }
            .max { lhs, rhs in
                let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left < right
            }
    }

    private struct Header {
        var id: String?
        var cwd: String?
        var timestamp: Date?
        var title: String
        var preview: String
    }

    private func readSession(at fileURL: URL, projectURL: URL) -> StoredSession? {
        guard let header = readHeader(of: fileURL) else { return nil }

        let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
        let modified = values?.contentModificationDate ?? header.timestamp ?? .distantPast
        let created = header.timestamp ?? values?.creationDate ?? modified

        return StoredSession(
            id: header.id ?? fileURL.lastPathComponent,
            fileURL: fileURL,
            projectURL: projectURL,
            title: header.title,
            preview: header.preview,
            createdAt: created,
            modifiedAt: modified
        )
    }

    /// Parses the title slot, session header and first user message from the file prefix.
    private func readHeader(of fileURL: URL) -> Header? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }

        guard
            let data = try? handle.read(upToCount: 96 * 1024),
            let text = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        var header = Header(title: "", preview: "")
        var sawSessionHeader = false
        let decoder = JSONDecoder()

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard
                let lineData = line.data(using: .utf8),
                let value = try? decoder.decode(JSONValue.self, from: lineData),
                let type = value["type"]?.stringValue
            else {
                continue
            }

            switch type {
            case "title":
                header.title = value["title"]?.stringValue?.trimmingCharacters(in: .whitespaces) ?? ""
            case "session":
                sawSessionHeader = true
                header.id = value["id"]?.stringValue
                header.cwd = value["cwd"]?.stringValue
                if let title = value["title"]?.stringValue, header.title.isEmpty {
                    header.title = title
                }
                if let timestamp = value["timestamp"]?.stringValue {
                    header.timestamp = ISO8601DateFormatter.fractional.date(from: timestamp)
                }
            case "message":
                guard
                    header.preview.isEmpty,
                    let message = try? value["message"]?.decoded(as: AgentMessage.self),
                    case .user(let user) = message,
                    !user.synthetic
                else {
                    continue
                }
                header.preview = String(user.content.joinedText.prefix(120))
                    .replacingOccurrences(of: "\n", with: " ")
                return header
            default:
                continue
            }
        }

        return sawSessionHeader ? header : nil
    }
}

extension ISO8601DateFormatter {
    nonisolated static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
