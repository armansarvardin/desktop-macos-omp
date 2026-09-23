//
//  AppStorageKeys.swift
//  OhMyPi
//
//  Created by Arman Sarvardin on 22/9/26.
//

import Foundation

extension String {
    /// Keys for `@AppStorage` / `UserDefaults`, kept in one place.
    nonisolated enum AppStorageKey {
        static let executablePath = "executablePath"
        static let useLoginShell = "useLoginShell"
        static let approvalMode = "approvalMode"
        static let extraArguments = "extraArguments"
        static let showThinking = "showThinking"
        static let recentProjects = "recentProjects"
    }
}

/// How the agent gates tool execution. `default` keeps the user's CLI config.
nonisolated enum ApprovalMode: String, CaseIterable, Identifiable, Sendable {
    case `default`
    case alwaysAsk = "always-ask"
    case write
    case yolo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .default: "Use CLI config"
        case .alwaysAsk: "Ask for writes and commands"
        case .write: "Ask for commands only"
        case .yolo: "Never ask"
        }
    }

    var argument: [String] {
        self == .default ? [] : ["--approval-mode", rawValue]
    }
}
