//
//  LaunchSettings.swift
//  OhMyPi
//
//  Created by Arman Sarvardin on 22/9/26.
//

import Foundation

/// How the app invokes `omp`, read from user defaults.
nonisolated struct LaunchSettings: Sendable, Hashable {
    var executable: String
    var useLoginShell: Bool
    var approvalMode: ApprovalMode
    var extraArguments: [String]

    static func current(defaults: UserDefaults = .standard) -> LaunchSettings {
        LaunchSettings(
            executable: defaults.string(forKey: .AppStorageKey.executablePath).flatMap { $0.isEmpty ? nil : $0 } ?? "omp",
            useLoginShell: defaults.object(forKey: .AppStorageKey.useLoginShell) as? Bool ?? true,
            approvalMode: ApprovalMode(rawValue: defaults.string(forKey: .AppStorageKey.approvalMode) ?? "") ?? .default,
            extraArguments: (defaults.string(forKey: .AppStorageKey.extraArguments) ?? "")
                .split(separator: " ", omittingEmptySubsequences: true)
                .map(String.init)
        )
    }

    /// Configuration for an interactive agent session in a project.
    func rpcConfiguration(for projectURL: URL, resume fileURL: URL?) -> RpcLaunchConfiguration {
        var arguments = ["--mode", "rpc-ui", "--cwd", projectURL.path]
        if let fileURL {
            arguments += ["--resume", fileURL.path]
        }
        arguments += approvalMode.argument
        arguments += extraArguments

        return RpcLaunchConfiguration(
            executable: executable,
            arguments: arguments,
            workingDirectory: projectURL,
            useLoginShell: useLoginShell
        )
    }

    /// Configuration for a throwaway agent used only to query the model catalog.
    func headlessRpcConfiguration() -> RpcLaunchConfiguration {
        RpcLaunchConfiguration(
            executable: executable,
            arguments: ["--mode", "rpc", "--no-session", "--cwd", NSTemporaryDirectory()],
            workingDirectory: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true),
            useLoginShell: useLoginShell
        )
    }
}
