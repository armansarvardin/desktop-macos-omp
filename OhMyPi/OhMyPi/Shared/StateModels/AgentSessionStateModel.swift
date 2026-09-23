//
//  AgentSessionStateModel.swift
//  OhMyPi
//
//  Created by Arman Sarvardin on 22/9/26.
//

import AppKit
import Foundation
import Observation

/// One running `omp` process bound to a project directory.
///
/// Owns the RPC client, folds events into the transcript and exposes
/// everything the chat screen needs to render and drive the agent.
@Observable
final class AgentSessionStateModel: Identifiable {
    enum Status: Equatable {
        case launching
        case ready
        case exited(code: Int32)
        case failed(String)

        var isAlive: Bool {
            switch self {
            case .launching, .ready: true
            case .exited, .failed: false
            }
        }
    }

    // MARK: - Stored properties

    let id: String
    let projectURL: URL
    let launcher: RpcLauncher
    let launchConfiguration: RpcLaunchConfiguration

    private(set) var status: Status = .launching
    private(set) var state: RpcSessionState?
    private(set) var transcript: [TranscriptItem] = []
    private(set) var availableModels: [RpcModel] = []
    private(set) var slashCommands: [RpcSlashCommand] = []
    private(set) var pendingUIRequests: [ExtensionUIRequest] = []
    private(set) var statusLines: [String: String] = [:]
    private(set) var banners: [Banner] = []
    private(set) var isStreaming = false
    private(set) var isLoadingHistory = false
    private(set) var title: String?
    private(set) var resumedFileURL: URL?
    /// Role the user picked explicitly; cleared when the model is changed another way.
    private(set) var selectedRoleName: String?

    var draft = ""

    private var client: RpcClient?
    private var reducer = TranscriptReducer()
    private var bannerCounter = 0

    struct Banner: Identifiable, Hashable {
        let id: Int
        var message: String
        var level: Notice.Level
    }

    // MARK: - Initialization

    init(
        projectURL: URL,
        resume fileURL: URL? = nil,
        title: String? = nil,
        launcher: RpcLauncher,
        launchConfiguration: RpcLaunchConfiguration
    ) {
        self.id = fileURL?.path ?? UUID().uuidString
        self.projectURL = projectURL
        self.resumedFileURL = fileURL
        self.title = title
        self.launcher = launcher
        self.launchConfiguration = launchConfiguration
    }

    // MARK: - Computed properties

    var projectName: String {
        projectURL.lastPathComponent
    }

    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        if let name = state?.sessionName, !name.isEmpty { return name }
        if let firstPrompt = transcript.lazy.compactMap({ item -> String? in
            if case .user(let user) = item.kind, !user.isCommand { user.text } else { nil }
        }).first {
            return String(firstPrompt.prefix(60))
        }
        return "New session"
    }

    var sessionFileURL: URL? {
        if let file = state?.sessionFile { return URL(fileURLWithPath: file) }
        return resumedFileURL
    }

    var currentModel: RpcModel? {
        state?.model
    }

    var thinkingLevel: ThinkingLevel? {
        state?.thinkingLevel.flatMap(ThinkingLevel.init(rawValue:))
    }

    /// The first UI request that blocks the agent until answered.
    var activeUIRequest: ExtensionUIRequest? {
        pendingUIRequests.first(where: \.expectsResponse)
    }

    /// The role that best describes the current model: the explicitly chosen one
    /// while it still matches, otherwise the first role (in cycle order) whose
    /// model and effort suffix both match the session state.
    func activeRole(in roles: [ModelRole]) -> ModelRole? {
        guard let current = currentModel else { return nil }

        func matches(_ role: ModelRole, requireEffort: Bool) -> Bool {
            guard let selector = ModelRoleResolver.resolve(role.name, in: roles),
                  selector.qualifiedId == current.qualifiedId
            else { return false }
            guard requireEffort, let effort = selector.effort else { return true }
            return effort == state?.thinkingLevel
        }

        if let selectedRoleName, let role = roles.first(where: { $0.name == selectedRoleName }), matches(role, requireEffort: false) {
            return role
        }
        return roles.first { matches($0, requireEffort: true) }
    }

    var canSend: Bool {
        status == .ready && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Lifecycle

    func start() async {
        guard client == nil else { return }

        do {
            let transport = try launcher.launch(launchConfiguration)
            let client = RpcClient(transport: transport)
            self.client = client

            client.onEvent = { [weak self] frame in
                self?.handle(frame: frame)
            }
            client.onExit = { [weak self] code, stderr in
                self?.handleExit(code: code, stderr: stderr)
            }

            try await client.waitUntilReady()
            try await client.request(.negotiateProtocol(version: 2))
            status = .ready
            await refreshState()
            await loadSlashCommands()

            if resumedFileURL != nil {
                await loadHistory()
            }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func stop() {
        client?.shutdown()
    }

    // MARK: - Prompting

    func sendDraft() {
        let message = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, let client else { return }

        let isCommand = message.hasPrefix("/")
        draft = ""
        reducer.appendLocalUserMessage(message, isSteering: isStreaming && !isCommand, isCommand: isCommand)
        publishTranscript()

        Task {
            do {
                if isCommand {
                    // Slash commands are dispatched by the runtime before prompting the model.
                    try await client.request(.prompt(message: message, streamingBehavior: isStreaming ? "steer" : nil))
                } else if isStreaming {
                    try await client.request(.steer(message: message))
                } else {
                    try await client.request(.prompt(message: message, streamingBehavior: nil))
                }
            } catch {
                showBanner(error.localizedDescription, level: .error)
            }
        }
    }

    /// Suggestions for the draft, or `nil` when the palette should be hidden.
    var slashSuggestions: [SlashSuggestion]? {
        SlashCommandMatcher.suggestions(for: draft, commands: slashCommands)
    }

    func accept(_ suggestion: SlashSuggestion) {
        draft = suggestion.completion
        if !suggestion.expectsInput {
            sendDraft()
        }
    }

    func queueFollowUp() {
        let message = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, let client else { return }

        draft = ""
        Task {
            do {
                try await client.request(.followUp(message: message))
                showBanner("Queued as a follow-up", level: .info)
            } catch {
                showBanner(error.localizedDescription, level: .error)
            }
        }
    }

    func abort() {
        Task {
            _ = try? await client?.request(.abort)
        }
    }

    func startNewSession() {
        Task {
            do {
                try await client?.request(.newSession)
                reducer.reset()
                publishTranscript()
                title = nil
                await refreshState()
            } catch {
                showBanner(error.localizedDescription, level: .error)
            }
        }
    }

    func compact() {
        Task {
            do {
                try await client?.request(.compact(customInstructions: nil))
                await refreshState()
            } catch {
                showBanner(error.localizedDescription, level: .error)
            }
        }
    }

    // MARK: - Model & thinking

    func loadAvailableModels() async {
        guard availableModels.isEmpty, let client else { return }

        do {
            let payload = try await client.request(.getAvailableModels)
            let models = try payload?["models"]?.decoded(as: [RpcModel].self) ?? []
            availableModels = models.sorted { lhs, rhs in
                (lhs.provider, lhs.name.lowercased()) < (rhs.provider, rhs.name.lowercased())
            }
        } catch {
            showBanner(error.localizedDescription, level: .error)
        }
    }

    func select(model: RpcModel) {
        selectedRoleName = nil
        Task {
            do {
                try await client?.request(.setModel(provider: model.provider, modelId: model.id))
                await refreshState()
            } catch {
                showBanner(error.localizedDescription, level: .error)
            }
        }
    }

    /// Switches this session to the model a role points at, including its effort suffix.
    func select(role: ModelRole, in roles: [ModelRole]) {
        guard
            let selector = ModelRoleResolver.resolve(role.name, in: roles),
            let qualifiedId = selector.qualifiedId,
            let parts = ModelRoleResolver.split(qualifiedId: qualifiedId)
        else {
            showBanner("Role \(role.name) does not point at a model", level: .warning)
            return
        }

        selectedRoleName = role.name
        Task {
            do {
                try await client?.request(.setModel(provider: parts.provider, modelId: parts.modelId))
                if let effort = selector.effort {
                    try await client?.request(.setThinkingLevel(effort))
                }
                await refreshState()
            } catch {
                showBanner(error.localizedDescription, level: .error)
            }
        }
    }

    func select(thinkingLevel: ThinkingLevel) {
        selectedRoleName = nil
        Task {
            do {
                try await client?.request(.setThinkingLevel(thinkingLevel.rawValue))
                await refreshState()
            } catch {
                showBanner(error.localizedDescription, level: .error)
            }
        }
    }

    func cycleModel() {
        selectedRoleName = nil
        Task {
            do {
                try await client?.request(.cycleModel)
                await refreshState()
            } catch {
                showBanner(error.localizedDescription, level: .error)
            }
        }
    }

    func toggleFastMode() {
        guard let state else { return }
        Task {
            _ = try? await client?.request(.setFastMode(!state.fastModeEnabled))
            await refreshState()
        }
    }

    // MARK: - Extension UI

    func respond(to request: ExtensionUIRequest, with response: ExtensionUIResponse) {
        client?.respond(to: request.id, with: response)
        pendingUIRequests.removeAll { $0.id == request.id }
    }

    func dismissBanner(_ banner: Banner) {
        banners.removeAll { $0.id == banner.id }
    }

    // MARK: - Private: state

    private func loadSlashCommands() async {
        guard slashCommands.isEmpty, let client else { return }
        if let payload = try? await client.request(.getAvailableCommands),
           let commands = try? payload["commands"]?.decoded(as: [RpcSlashCommand].self)
        {
            slashCommands = commands
        }
    }

    private func refreshState() async {
        guard let client else { return }
        do {
            state = try await client.request(.getState, as: RpcSessionState.self)
            isStreaming = state?.isStreaming ?? isStreaming
        } catch {
            showBanner(error.localizedDescription, level: .error)
        }
    }

    private func loadHistory() async {
        guard let client else { return }
        isLoadingHistory = true
        defer { isLoadingHistory = false }

        var messages: [AgentMessage] = []
        var cursor: String?

        do {
            repeat {
                let page = try await client.request(.getMessagesPage(cursor: cursor, limit: 200), as: RpcMessagesPage.self)
                messages.append(contentsOf: page.messages)
                cursor = page.nextCursor
            } while cursor != nil

            reducer.load(messages: messages)
            publishTranscript()
        } catch {
            showBanner("Could not load history: \(error.localizedDescription)", level: .warning)
        }
    }

    private func publishTranscript() {
        transcript = reducer.items
    }

    private func showBanner(_ message: String, level: Notice.Level) {
        bannerCounter += 1
        let banner = Banner(id: bannerCounter, message: message, level: level)
        banners.append(banner)

        Task {
            try? await Task.sleep(for: .seconds(5))
            banners.removeAll { $0.id == banner.id }
        }
    }

    // MARK: - Private: events

    private func handle(frame: JSONValue) {
        guard let type = frame["type"]?.stringValue else { return }

        switch type {
        case "agent_start":
            isStreaming = true
            reducer.apply(event: frame)

        case "agent_end":
            reducer.apply(event: frame)
            if frame["isTerminal"]?.boolValue != false {
                isStreaming = false
                Task { await refreshState() }
            }
            publishTranscript()

        case "message_start", "message_update", "message_end",
             "tool_execution_start", "tool_execution_end", "notice", "auto_compaction_end":
            reducer.apply(event: frame)
            publishTranscript()

        case "model_changed", "thinking_level_changed", "config_update":
            Task { await refreshState() }

        case "command_output":
            reducer.appendCommandOutput(frame["text"]?.stringValue ?? "")
            publishTranscript()

        case "session_info_update":
            if let updated = frame["title"]?.stringValue, !updated.isEmpty {
                title = updated
            }

        case "available_commands_update":
            slashCommands = (try? frame["commands"]?.decoded(as: [RpcSlashCommand].self)) ?? slashCommands

        case "extension_ui_request":
            guard let request = ExtensionUIRequest(frame: frame) else { return }
            handle(uiRequest: request)

        case "auto_retry_start":
            let attempt = frame["attempt"]?.intValue ?? 0
            let max = frame["maxAttempts"]?.intValue ?? 0
            showBanner("Retrying request (\(attempt)/\(max))…", level: .warning)

        case "rpc_frame_error", "extension_error":
            showBanner(frame["error"]?.stringValue ?? "Protocol error", level: .error)

        default:
            break
        }
    }

    private func handle(uiRequest request: ExtensionUIRequest) {
        switch request.method {
        case .select, .confirm, .input, .editor:
            pendingUIRequests.append(request)

        case .openURL(let url, let instructions):
            if let url = URL(string: url) {
                NSWorkspace.shared.open(url)
            }
            showBanner(instructions ?? "Opened \(url) in your browser", level: .info)

        case .notify(let message, let level):
            showBanner(message, level: Notice.Level(rawValue: level) ?? .info)

        case .setStatus(let key, let text):
            statusLines[key] = text

        case .setTitle(let newTitle):
            title = newTitle

        case .setEditorText(let text):
            draft = text

        case .cancel(let targetId):
            pendingUIRequests.removeAll { $0.id == targetId }

        case .setWidget, .unknown:
            break
        }
    }

    private func handleExit(code: Int32, stderr: String) {
        isStreaming = false
        pendingUIRequests.removeAll()

        if case .failed = status { return }
        status = .exited(code: code)

        let tail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if code != 0, !tail.isEmpty {
            reducer.appendNotice(Notice(level: .error, message: tail.suffix(1_000).description, source: "stderr"))
            publishTranscript()
        }
    }
}
