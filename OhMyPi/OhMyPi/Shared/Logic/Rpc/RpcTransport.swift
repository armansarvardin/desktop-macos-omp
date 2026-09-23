//
//  RpcTransport.swift
//  OhMyPi
//
//  Created by Arman Sarvardin on 22/9/26.
//

import Foundation

/// How the agent process gets launched.
nonisolated struct RpcLaunchConfiguration: Sendable, Hashable {
    var executable: String
    var arguments: [String]
    var workingDirectory: URL
    var useLoginShell: Bool
    var environment: [String: String]

    nonisolated init(
        executable: String,
        arguments: [String],
        workingDirectory: URL,
        useLoginShell: Bool = true,
        environment: [String: String] = [:]
    ) {
        self.executable = executable
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.useLoginShell = useLoginShell
        self.environment = environment
    }
}

/// Bidirectional JSONL stream to an agent process.
nonisolated protocol RpcTransport: AnyObject, Sendable {
    /// Logical frames after protocol v2 chunk reassembly, delivered in order.
    var frames: AsyncStream<JSONValue> { get }
    /// Resolves with the exit code once the process is gone.
    var exitCode: Int32? { get }
    func send(_ frame: JSONValue) throws
    func closeInput()
    func terminate()
}

/// Factory for transports so previews and tests can swap the live process out.
nonisolated struct RpcLauncher: Sendable {
    let launch: @Sendable (RpcLaunchConfiguration) throws -> any RpcTransport

    static let `default` = RpcLauncher { configuration in
        try ProcessRpcTransport(configuration: configuration)
    }
}

// MARK: - Live process transport

/// Spawns `omp --mode rpc-ui` and shuttles newline-delimited JSON over its pipes.
nonisolated final class ProcessRpcTransport: RpcTransport, @unchecked Sendable {
    let frames: AsyncStream<JSONValue>

    private let process = Process()
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let writeQueue = DispatchQueue(label: "sh.omp.desktop.rpc.write")
    private let continuation: AsyncStream<JSONValue>.Continuation
    private let decoder = RpcFrameDecoder()
    private let lock = NSLock()
    private var buffer = Data()
    private var stderrTail = ""
    private var inputClosed = false
    private var _exitCode: Int32?

    var exitCode: Int32? {
        lock.withLock { _exitCode }
    }

    /// Last lines the process wrote to stderr, for diagnostics.
    var recentStderr: String {
        lock.withLock { stderrTail }
    }

    init(configuration: RpcLaunchConfiguration) throws {
        var continuation: AsyncStream<JSONValue>.Continuation!
        frames = AsyncStream(bufferingPolicy: .unbounded) { continuation = $0 }
        self.continuation = continuation

        if configuration.useLoginShell {
            // Interactive login shell so user aliases, functions and PATH apply.
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            // `$0` receives the executable so shell functions and PATH lookups both resolve.
            process.arguments = ["-lic", "\"$0\" \"$@\"", configuration.executable] + configuration.arguments
        } else {
            let expanded = (configuration.executable as NSString).expandingTildeInPath
            guard FileManager.default.isExecutableFile(atPath: expanded) else {
                throw RpcError.executableNotFound(expanded)
            }
            process.executableURL = URL(fileURLWithPath: expanded)
            process.arguments = configuration.arguments
        }

        var environment = ProcessInfo.processInfo.environment
        environment.merge(configuration.environment) { _, override in override }
        environment["PI_RPC_EMIT_TITLE"] = "1"
        process.environment = environment
        process.currentDirectoryURL = configuration.workingDirectory
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.consume(handle.availableData)
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.consumeStderr(handle.availableData)
        }

        process.terminationHandler = { [weak self] process in
            self?.finish(exitCode: process.terminationStatus)
        }

        try process.run()
    }

    deinit {
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        continuation.finish()
    }

    // MARK: - RpcTransport

    func send(_ frame: JSONValue) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        var data = try encoder.encode(frame)
        data.append(0x0A)

        writeQueue.async { [stdinPipe, lock] in
            let closed = lock.withLock { self.inputClosed }
            guard !closed else { return }
            try? stdinPipe.fileHandleForWriting.write(contentsOf: data)
        }
    }

    func closeInput() {
        writeQueue.async { [stdinPipe, lock] in
            let alreadyClosed = lock.withLock { () -> Bool in
                defer { self.inputClosed = true }
                return self.inputClosed
            }
            guard !alreadyClosed else { return }
            try? stdinPipe.fileHandleForWriting.close()
        }
    }

    func terminate() {
        closeInput()
        guard process.isRunning else { return }

        // Give the agent a moment to drain and exit cleanly on stdin EOF.
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [process] in
            if process.isRunning {
                process.terminate()
            }
        }
    }

    // MARK: - Reading

    private func consume(_ data: Data) {
        guard !data.isEmpty else {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            return
        }

        var lines: [Data] = []

        lock.withLock {
            buffer.append(data)
            while let newline = buffer.firstIndex(of: 0x0A) {
                lines.append(buffer.subdata(in: buffer.startIndex..<newline))
                buffer.removeSubrange(buffer.startIndex...newline)
            }
        }

        for line in lines where !line.isEmpty {
            do {
                let raw = try JSONDecoder().decode(JSONValue.self, from: line)
                if let frame = try decoder.push(raw) {
                    continuation.yield(frame)
                }
            } catch {
                continuation.yield(
                    .object([
                        "type": "rpc_frame_error",
                        "error": .string(error.localizedDescription)
                    ])
                )
            }
        }
    }

    private func consumeStderr(_ data: Data) {
        guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
            if data.isEmpty {
                stderrPipe.fileHandleForReading.readabilityHandler = nil
            }
            return
        }

        lock.withLock {
            stderrTail = String((stderrTail + text).suffix(4_000))
        }
    }

    private func finish(exitCode: Int32) {
        // Drain whatever is left before reporting exit.
        let remaining = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        if !remaining.isEmpty {
            consume(remaining + Data([0x0A]))
        }

        lock.withLock { _exitCode = exitCode }
        continuation.yield(
            .object([
                "type": "process_exit",
                "code": .number(Double(exitCode)),
                "stderr": .string(recentStderr)
            ])
        )
        continuation.finish()
    }
}

// MARK: - Chunk reassembly

/// Reassembles protocol v2 `rpc_chunk` frames into one logical frame.
nonisolated final class RpcFrameDecoder: @unchecked Sendable {
    private struct Pending {
        var chunkId: String
        var count: Int
        var byteLength: Int
        var nextIndex: Int
        var data = Data()
    }

    private var pending: Pending?
    private let lock = NSLock()

    /// Returns a complete frame, or `nil` while a chunk sequence is still in flight.
    func push(_ value: JSONValue) throws -> JSONValue? {
        guard value["type"]?.stringValue == "rpc_chunk" else {
            try lock.withLock {
                if pending != nil {
                    pending = nil
                    throw RpcError.malformedFrame("chunk sequence interrupted")
                }
            }
            return value
        }

        guard
            let chunkId = value["chunkId"]?.stringValue,
            let index = value["index"]?.intValue,
            let count = value["count"]?.intValue,
            let byteLength = value["byteLength"]?.intValue,
            let base64 = value["data"]?.stringValue,
            let bytes = Data(base64Encoded: base64)
        else {
            throw RpcError.malformedFrame("invalid chunk metadata")
        }

        return try lock.withLock {
            if pending == nil {
                guard index == 0 else {
                    throw RpcError.malformedFrame("chunk sequence must start at index 0")
                }
                pending = Pending(chunkId: chunkId, count: count, byteLength: byteLength, nextIndex: 0)
            }

            guard
                var current = pending,
                current.chunkId == chunkId,
                current.count == count,
                current.nextIndex == index
            else {
                pending = nil
                throw RpcError.malformedFrame("chunk sequence mismatch")
            }

            current.data.append(bytes)
            current.nextIndex += 1

            guard current.nextIndex == current.count else {
                pending = current
                return nil
            }

            pending = nil

            guard current.data.count == current.byteLength else {
                throw RpcError.malformedFrame("chunk sequence length mismatch")
            }

            return try JSONDecoder().decode(JSONValue.self, from: current.data)
        }
    }
}
