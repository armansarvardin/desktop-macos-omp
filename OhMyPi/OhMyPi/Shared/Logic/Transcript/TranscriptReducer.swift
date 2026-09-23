//
//  TranscriptReducer.swift
//  OhMyPi
//
//  Created by Arman Sarvardin on 22/9/26.
//

import Foundation

/// Folds RPC agent events and stored messages into transcript rows.
///
/// Streaming text is accumulated from `text_delta` events; the `message_end`
/// frame is treated as the authoritative final content.
nonisolated struct TranscriptReducer: Sendable {
    private(set) var items: [TranscriptItem] = []

    private var toolCallLocations: [String: (item: Int, block: Int)] = [:]
    private var streamingIndex: Int?
    private var counter = 0

    // MARK: - Mutations

    mutating func reset() {
        items.removeAll()
        toolCallLocations.removeAll()
        streamingIndex = nil
    }

    /// Replaces the transcript with a stored history.
    mutating func load(messages: [AgentMessage]) {
        reset()
        messages.forEach { append(message: $0, streaming: false) }
    }

    /// Adds the user's message immediately, before the runtime echoes it.
    mutating func appendLocalUserMessage(_ text: String, isSteering: Bool, isCommand: Bool = false) {
        items.append(
            TranscriptItem(
                id: nextId("local"),
                kind: .user(
                    UserContent(text: text, imageCount: 0, isSteering: isSteering, isPending: !isCommand, isCommand: isCommand)
                ),
                timestamp: .now
            )
        )
    }

    /// Output of a builtin slash command (`command_output` frame).
    mutating func appendCommandOutput(_ text: String) {
        let cleaned = text.strippingANSI.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        items.append(TranscriptItem(id: nextId("command"), kind: .commandOutput(cleaned), timestamp: .now))
    }

    mutating func appendNotice(_ notice: Notice) {
        items.append(TranscriptItem(id: nextId("notice"), kind: .notice(notice), timestamp: .now))
    }

    /// Applies one agent event frame. Non-transcript frames are ignored.
    mutating func apply(event: JSONValue) {
        guard let type = event["type"]?.stringValue else { return }

        switch type {
        case "message_start":
            guard let message = decodeMessage(event["message"]) else { return }
            append(message: message, streaming: true)

        case "message_update":
            applyAssistantUpdate(event["assistantMessageEvent"])

        case "message_end":
            guard let message = decodeMessage(event["message"]) else { return }
            finish(message: message)

        case "tool_execution_start":
            guard let toolCallId = event["toolCallId"]?.stringValue else { return }
            let name = event["toolName"]?.stringValue ?? "tool"
            let arguments = event["args"] ?? .object([:])
            ensureToolCall(id: toolCallId, name: name, arguments: arguments)
            updateToolCall(id: toolCallId) { $0.status = .running }

        case "tool_execution_end":
            guard let toolCallId = event["toolCallId"]?.stringValue else { return }
            let result = (try? event["result"]?.decoded(as: AgentToolResult.self))
                ?? AgentToolResult(content: [.text(event["result"]?.stringValue ?? "")])
            let isError = event["isError"]?.boolValue ?? result.isError ?? false
            updateToolCall(id: toolCallId) { call in
                call.status = isError ? .failed : .succeeded
                call.resultText = result.content.joinedText
                call.resultImageCount = result.content.filter { if case .image = $0 { true } else { false } }.count
                call.details = result.details
            }

        case "notice":
            appendNotice(
                Notice(
                    level: Notice.Level(rawValue: event["level"]?.stringValue ?? "info") ?? .info,
                    message: event["message"]?.stringValue ?? "",
                    source: event["source"]?.stringValue
                )
            )

        case "auto_compaction_end":
            guard event["skipped"]?.boolValue != true, event["aborted"]?.boolValue != true else { return }
            let summary = event["result"]?["summary"]?.stringValue ?? "Context was compacted."
            items.append(TranscriptItem(id: nextId("compaction"), kind: .compaction(summary), timestamp: .now))

        case "agent_end":
            if let index = streamingIndex, case .assistant(var content) = items[index].kind {
                content.isStreaming = false
                items[index].kind = .assistant(content)
            }
            streamingIndex = nil

        default:
            break
        }
    }

    // MARK: - Messages

    private mutating func append(message: AgentMessage, streaming: Bool) {
        switch message {
        case .user(let user):
            guard !user.synthetic else { return }
            let text = user.content.joinedText
            let imageCount = user.content.filter { if case .image = $0 { true } else { false } }.count

            if
                let last = items.indices.last,
                case .user(var pending) = items[last].kind,
                pending.isPending,
                pending.text == text
            {
                pending.isPending = false
                pending.imageCount = imageCount
                items[last].kind = .user(pending)
                return
            }

            items.append(
                TranscriptItem(
                    id: nextId("user"),
                    kind: .user(UserContent(text: text, imageCount: imageCount, isSteering: user.steering, isPending: false)),
                    timestamp: date(fromMilliseconds: user.timestamp)
                )
            )

        case .assistant(let assistant):
            let id = nextId("assistant")
            let blocks = assistant.content.enumerated().compactMap { index, block in
                makeBlock(id: "\(id)-\(index)", content: block)
            }

            items.append(
                TranscriptItem(
                    id: id,
                    kind: .assistant(
                        AssistantContent(
                            blocks: blocks,
                            model: assistant.model,
                            isStreaming: streaming,
                            errorMessage: errorMessage(for: assistant)
                        )
                    ),
                    timestamp: date(fromMilliseconds: assistant.timestamp)
                )
            )

            let itemIndex = items.count - 1
            registerToolCalls(in: blocks, itemIndex: itemIndex)
            streamingIndex = streaming ? itemIndex : nil

        case .toolResult(let result):
            ensureToolCall(id: result.toolCallId, name: result.toolName, arguments: .object([:]))
            updateToolCall(id: result.toolCallId) { call in
                call.status = result.isError ? .failed : .succeeded
                call.resultText = result.content.joinedText
                call.resultImageCount = result.content.filter { if case .image = $0 { true } else { false } }.count
                call.details = result.details
            }

        case .other:
            break
        }
    }

    private mutating func finish(message: AgentMessage) {
        switch message {
        case .assistant(let assistant):
            guard let index = streamingIndex, case .assistant(var content) = items[index].kind else {
                append(message: message, streaming: false)
                return
            }

            let existingCalls = Dictionary(
                content.blocks.compactMap { block -> (String, ToolCallState)? in
                    if case .toolCall(let call) = block.kind { (call.id, call) } else { nil }
                },
                uniquingKeysWith: { first, _ in first }
            )

            content.blocks = assistant.content.enumerated().compactMap { blockIndex, block in
                guard var made = makeBlock(id: "\(items[index].id)-\(blockIndex)", content: block) else {
                    return nil
                }
                if case .toolCall(var call) = made.kind, let existing = existingCalls[call.id] {
                    call.status = existing.status
                    call.resultText = existing.resultText
                    call.resultImageCount = existing.resultImageCount
                    call.details = existing.details
                    made.kind = .toolCall(call)
                }
                return made
            }
            content.isStreaming = false
            content.model = assistant.model ?? content.model
            content.errorMessage = errorMessage(for: assistant)
            items[index].kind = .assistant(content)
            registerToolCalls(in: content.blocks, itemIndex: index)
            streamingIndex = nil

        case .user(let user):
            // `message_start` already appended this row; only confirm it.
            let text = user.content.joinedText
            if let last = items.lastIndex(where: { if case .user = $0.kind { true } else { false } }),
               case .user(var existing) = items[last].kind,
               existing.text == text
            {
                existing.isPending = false
                items[last].kind = .user(existing)
            } else {
                append(message: message, streaming: false)
            }

        case .toolResult:
            append(message: message, streaming: false)

        case .other:
            break
        }
    }

    // MARK: - Streaming updates

    private mutating func applyAssistantUpdate(_ event: JSONValue?) {
        guard
            let event,
            let type = event["type"]?.stringValue,
            let index = streamingIndex,
            case .assistant(var content) = items[index].kind
        else {
            return
        }

        let contentIndex = event["contentIndex"]?.intValue ?? content.blocks.count
        let blockId = "\(items[index].id)-\(contentIndex)"

        func setBlock(_ kind: AssistantBlock.Kind) {
            if content.blocks.indices.contains(contentIndex) {
                content.blocks[contentIndex].kind = kind
            } else {
                while content.blocks.count < contentIndex {
                    content.blocks.append(AssistantBlock(id: "\(items[index].id)-\(content.blocks.count)", kind: .text("")))
                }
                content.blocks.append(AssistantBlock(id: blockId, kind: kind))
            }
        }

        switch type {
        case "text_start":
            setBlock(.text(""))
        case "text_delta":
            let delta = event["delta"]?.stringValue ?? ""
            if content.blocks.indices.contains(contentIndex), case .text(let text) = content.blocks[contentIndex].kind {
                content.blocks[contentIndex].kind = .text(text + delta)
            } else {
                setBlock(.text(delta))
            }
        case "text_end":
            setBlock(.text(event["content"]?.stringValue ?? ""))
        case "thinking_start":
            setBlock(.thinking(""))
        case "thinking_delta":
            let delta = event["delta"]?.stringValue ?? ""
            if content.blocks.indices.contains(contentIndex), case .thinking(let text) = content.blocks[contentIndex].kind {
                content.blocks[contentIndex].kind = .thinking(text + delta)
            } else {
                setBlock(.thinking(delta))
            }
        case "thinking_end":
            setBlock(.thinking(event["content"]?.stringValue ?? ""))
        case "toolcall_start":
            setBlock(.toolCall(ToolCallState(id: blockId, name: "…", arguments: .object([:]), status: .pending, resultText: "", resultImageCount: 0)))
        case "toolcall_end":
            if case .toolCall(let id, let name, let arguments) = decodeContent(event["toolCall"]) {
                setBlock(.toolCall(ToolCallState(id: id, name: name, arguments: arguments, status: .pending, resultText: "", resultImageCount: 0)))
                toolCallLocations[id] = (index, contentIndex)
            }
        case "image_end":
            setBlock(.image(mimeType: event["content"]?["mimeType"]?.stringValue ?? "image"))
        case "error":
            content.errorMessage = event["error"]?["errorMessage"]?.stringValue
                ?? "Response \(event["reason"]?.stringValue ?? "failed")"
        default:
            break
        }

        items[index].kind = .assistant(content)
    }

    // MARK: - Tool calls

    private mutating func ensureToolCall(id: String, name: String, arguments: JSONValue) {
        guard toolCallLocations[id] == nil else { return }

        let call = ToolCallState(id: id, name: name, arguments: arguments, status: .pending, resultText: "", resultImageCount: 0)

        if let index = streamingIndex, case .assistant(var content) = items[index].kind {
            content.blocks.append(AssistantBlock(id: "\(items[index].id)-\(content.blocks.count)", kind: .toolCall(call)))
            items[index].kind = .assistant(content)
            toolCallLocations[id] = (index, content.blocks.count - 1)
            return
        }

        let itemId = nextId("assistant")
        items.append(
            TranscriptItem(
                id: itemId,
                kind: .assistant(
                    AssistantContent(
                        blocks: [AssistantBlock(id: "\(itemId)-0", kind: .toolCall(call))],
                        model: nil,
                        isStreaming: false,
                        errorMessage: nil
                    )
                ),
                timestamp: .now
            )
        )
        toolCallLocations[id] = (items.count - 1, 0)
    }

    private mutating func updateToolCall(id: String, _ mutate: (inout ToolCallState) -> Void) {
        guard
            let location = toolCallLocations[id],
            items.indices.contains(location.item),
            case .assistant(var content) = items[location.item].kind,
            content.blocks.indices.contains(location.block),
            case .toolCall(var call) = content.blocks[location.block].kind
        else {
            return
        }

        mutate(&call)
        content.blocks[location.block].kind = .toolCall(call)
        items[location.item].kind = .assistant(content)
    }

    private mutating func registerToolCalls(in blocks: [AssistantBlock], itemIndex: Int) {
        for (blockIndex, block) in blocks.enumerated() {
            if case .toolCall(let call) = block.kind {
                toolCallLocations[call.id] = (itemIndex, blockIndex)
            }
        }
    }

    // MARK: - Helpers

    private func makeBlock(id: String, content: MessageContent) -> AssistantBlock? {
        switch content {
        case .text(let text):
            AssistantBlock(id: id, kind: .text(text))
        case .thinking(let thinking):
            AssistantBlock(id: id, kind: .thinking(thinking))
        case .toolCall(let callId, let name, let arguments):
            AssistantBlock(
                id: id,
                kind: .toolCall(
                    ToolCallState(id: callId, name: name, arguments: arguments, status: .pending, resultText: "", resultImageCount: 0)
                )
            )
        case .image(let mimeType):
            AssistantBlock(id: id, kind: .image(mimeType: mimeType))
        case .other:
            nil
        }
    }

    private func errorMessage(for assistant: AgentMessage.Assistant) -> String? {
        if let errorMessage = assistant.errorMessage, !errorMessage.isEmpty {
            return errorMessage
        }
        switch assistant.stopReason {
        case "aborted": return "Aborted"
        case "error": return "The model returned an error"
        default: return nil
        }
    }

    private func decodeMessage(_ value: JSONValue?) -> AgentMessage? {
        guard let value else { return nil }
        return try? value.decoded(as: AgentMessage.self)
    }

    private func decodeContent(_ value: JSONValue?) -> MessageContent? {
        guard let value else { return nil }
        return try? value.decoded(as: MessageContent.self)
    }

    private func date(fromMilliseconds milliseconds: Double?) -> Date {
        guard let milliseconds else { return .now }
        return Date(timeIntervalSince1970: milliseconds / 1_000)
    }

    private mutating func nextId(_ prefix: String) -> String {
        counter += 1
        return "\(prefix)-\(counter)"
    }
}
