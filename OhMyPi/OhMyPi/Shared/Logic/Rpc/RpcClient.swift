//
//  RpcClient.swift
//  OhMyPi
//
//  Created by Arman Sarvardin on 22/9/26.
//

import Foundation

/// Typed request/response layer over an `RpcTransport`.
///
/// Responses are matched by correlation id; every other frame (agent events,
/// extension UI requests, notices) is forwarded to `onEvent` in arrival order.
@MainActor
final class RpcClient {
    private(set) var isReady = false
    private(set) var protocolVersion = 1

    var onEvent: (JSONValue) -> Void = { _ in }
    var onExit: (Int32, String) -> Void = { _, _ in }

    private let transport: any RpcTransport
    private var pending: [String: CheckedContinuation<JSONValue?, Error>] = [:]
    private var readyContinuations: [CheckedContinuation<Void, Error>] = []
    private var nextRequestNumber = 0
    private var readerTask: Task<Void, Never>?
    private var exited = false

    init(transport: any RpcTransport) {
        self.transport = transport

        readerTask = Task { [weak self] in
            for await frame in transport.frames {
                guard let self else { return }
                self.receive(frame)
            }
            self?.handleStreamEnd()
        }
    }

    deinit {
        readerTask?.cancel()
    }

    // MARK: - Lifecycle

    /// Suspends until the process emitted its `ready` frame.
    func waitUntilReady() async throws {
        guard !isReady else { return }
        guard !exited else { throw RpcError.transportClosed }

        try await withCheckedThrowingContinuation { continuation in
            readyContinuations.append(continuation)
        }
    }

    func shutdown() {
        transport.terminate()
    }

    // MARK: - Requests

    /// Sends a command and returns the `data` of its response, if any.
    @discardableResult
    func request(_ command: RpcCommand) async throws -> JSONValue? {
        guard !exited else { throw RpcError.transportClosed }

        nextRequestNumber += 1
        let id = "req_\(nextRequestNumber)"

        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation

            do {
                try transport.send(command.payload(id: id))
            } catch {
                pending[id] = nil
                continuation.resume(throwing: error)
            }
        }
    }

    /// Sends a command and decodes its `data` into a concrete type.
    func request<Value: Decodable>(_ command: RpcCommand, as type: Value.Type) async throws -> Value {
        guard let data = try await request(command) else {
            throw RpcError.commandFailed(command: command.name, message: "empty response", code: nil)
        }
        return try data.decoded(as: Value.self)
    }

    func respond(to requestId: String, with response: ExtensionUIResponse) {
        try? transport.send(response.payload(id: requestId))
    }

    // MARK: - Receiving

    private func receive(_ frame: JSONValue) {
        guard let type = frame["type"]?.stringValue else { return }

        switch type {
        case "ready":
            isReady = true
            let continuations = readyContinuations
            readyContinuations.removeAll()
            continuations.forEach { $0.resume() }
            onEvent(frame)

        case "response":
            resolve(frame)

        case "process_exit":
            let code = Int32(frame["code"]?.intValue ?? -1)
            let stderr = frame["stderr"]?.stringValue ?? ""
            markExited(code: code, stderr: stderr)

        default:
            onEvent(frame)
        }
    }

    private func resolve(_ frame: JSONValue) {
        let command = frame["command"]?.stringValue ?? "unknown"

        guard
            let id = frame["id"]?.stringValue,
            let continuation = pending.removeValue(forKey: id)
        else {
            // Unsolicited or unknown-command responses are surfaced as events.
            onEvent(frame)
            return
        }

        if frame["success"]?.boolValue == true {
            if command == "negotiate_protocol", let version = frame["data"]?["protocolVersion"]?.intValue {
                protocolVersion = version
            }
            continuation.resume(returning: frame["data"])
        } else {
            continuation.resume(
                throwing: RpcError.commandFailed(
                    command: command,
                    message: frame["error"]?.stringValue ?? "Unknown error",
                    code: frame["code"]?.stringValue
                )
            )
        }
    }

    private func handleStreamEnd() {
        guard !exited else { return }
        markExited(code: transport.exitCode ?? -1, stderr: "")
    }

    private func markExited(code: Int32, stderr: String) {
        guard !exited else { return }
        exited = true

        let failures = pending.values
        pending.removeAll()
        failures.forEach { $0.resume(throwing: RpcError.processExited(code: code)) }

        let waiting = readyContinuations
        readyContinuations.removeAll()
        waiting.forEach { $0.resume(throwing: RpcError.processExited(code: code)) }

        onExit(code, stderr)
    }
}
