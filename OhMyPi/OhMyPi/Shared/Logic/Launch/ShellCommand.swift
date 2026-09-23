//
//  ShellCommand.swift
//  OhMyPi
//
//  Created by Arman Sarvardin on 22/9/26.
//

import Foundation

/// Runs one non-interactive `omp` invocation and collects its output.
nonisolated enum ShellCommand {
    struct Output: Sendable {
        var stdout: String
        var stderr: String
        var exitCode: Int32

        var succeeded: Bool { exitCode == 0 }
    }

    enum Failure: LocalizedError {
        case nonZeroExit(Int32, String)

        var errorDescription: String? {
            switch self {
            case .nonZeroExit(let code, let stderr):
                stderr.isEmpty ? "Command exited with code \(code)" : stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }

    /// Pipe contents filled from reader threads; each field is written exactly once.
    private final class CapturedOutput: @unchecked Sendable {
        var stdout = Data()
        var stderr = Data()
    }

    static func run(
        executable: String,
        arguments: [String],
        useLoginShell: Bool,
        currentDirectory: URL? = nil
    ) async throws -> Output {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            if useLoginShell {
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-lic", "\"$0\" \"$@\"", executable] + arguments
            } else {
                let expanded = (executable as NSString).expandingTildeInPath
                guard FileManager.default.isExecutableFile(atPath: expanded) else {
                    continuation.resume(throwing: RpcError.executableNotFound(expanded))
                    return
                }
                process.executableURL = URL(fileURLWithPath: expanded)
                process.arguments = arguments
            }

            process.currentDirectoryURL = currentDirectory
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            // Drain both pipes while the process runs; large outputs such as the
            // model catalog would otherwise fill the pipe and block the child.
            let group = DispatchGroup()
            let captured = CapturedOutput()

            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                captured.stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                captured.stderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }

            process.terminationHandler = { process in
                group.notify(queue: .global()) {
                    continuation.resume(
                        returning: Output(
                            stdout: String(data: captured.stdout, encoding: .utf8) ?? "",
                            stderr: String(data: captured.stderr, encoding: .utf8) ?? "",
                            exitCode: process.terminationStatus
                        )
                    )
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
