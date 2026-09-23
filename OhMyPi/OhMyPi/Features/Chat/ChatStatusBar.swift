//
//  ChatStatusBar.swift
//  OhMyPi
//
//  Created by Arman Sarvardin on 22/9/26.
//

import SwiftUI

/// Bottom strip with model and thinking-level controls, context usage and throughput.
struct ChatStatusBar: View {
    @Environment(WorkspaceStateModel.self) private var workspaceStateModel
    @Environment(\.appCommands) private var appCommands

    let session: AgentSessionStateModel

    @State private var isModelPickerPresented = false

    var body: some View {
        HStack(spacing: 8) {
            modelControl

            thinkingControl

            if let usage = session.state?.contextUsage {
                StatusPill(
                    title: "\(usage.tokens.formatted()) / \(usage.contextWindow.formatted()) (\(Int(usage.percent))%)",
                    systemImage: "gauge.with.dots.needle.33percent",
                    tint: usage.percent > 80 ? .red : usage.percent > 60 ? .orange : .green
                )
                .help("Context window usage")
            }

            if let tokensPerSecond = session.state?.tokensPerSecond, tokensPerSecond > 0 {
                StatusPill(title: "\(Int(tokensPerSecond)) tok/s", systemImage: "speedometer")
            }

            if session.state?.fastModeEnabled == true {
                StatusPill(title: "fast", systemImage: "hare", tint: .orange)
            }

            if let queued = session.state?.queuedMessageCount, queued > 0 {
                StatusPill(title: "\(queued) queued", systemImage: "tray.full")
            }

            ForEach(session.statusLines.sorted(by: { $0.key < $1.key }), id: \.key) { _, text in
                StatusPill(title: text, systemImage: "puzzlepiece.extension")
            }

            Spacer()

            statusText
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .sheet(isPresented: $isModelPickerPresented) {
            ModelPicker(session: session)
        }
    }

    // MARK: - Controls

    /// Click to open the model picker; secondary click cycles through configured roles.
    private var modelControl: some View {
        Menu {
            Section("Roles") {
                ForEach(workspaceStateModel.switchableRoles) { role in
                    Button {
                        session.select(role: role, in: workspaceStateModel.roles)
                    } label: {
                        if isCurrent(role) {
                            Label(roleTitle(role), systemImage: "checkmark")
                        } else {
                            Text(verbatim: roleTitle(role))
                        }
                    }
                }
                Button("Edit Roles…", systemImage: "slider.horizontal.3") {
                    appCommands.send(.showModelRoles)
                }
            }

            Divider()

            Button("Choose Model…", systemImage: "cpu") {
                isModelPickerPresented = true
            }
            Button("Cycle Model", systemImage: "arrow.triangle.2.circlepath") {
                session.cycleModel()
            }
            Button(session.state?.fastModeEnabled == true ? "Disable Fast Mode" : "Enable Fast Mode", systemImage: "hare") {
                session.toggleFastMode()
            }
        } label: {
            // Menu labels render a single view, so role and model share one pill.
            StatusPill(
                title: [activeRole?.name, session.currentModel.map { "\($0.provider)/\($0.id)" } ?? "Model"]
                    .compactMap { $0 }
                    .joined(separator: " · "),
                systemImage: "cpu",
                tint: activeRole.map(roleTint) ?? (session.currentModel == nil ? .secondary : .primary)
            )
        } primaryAction: {
            isModelPickerPresented = true
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(session.currentModel?.name ?? "Choose model")
        .disabled(session.status != .ready)
    }

    /// First role (in cycle order) whose model is the session's current one.
    private var activeRole: ModelRole? {
        session.activeRole(in: workspaceStateModel.switchableRoles)
    }

    private func roleTint(_ role: ModelRole) -> Color {
        switch role.color {
        case "accent": .accentColor
        case "success": .green
        case "warning": .orange
        case "error": .red
        case "info": .blue
        default: .secondary
        }
    }

    /// "Fast (smol) · Claude Opus 4.6" style menu title.
    private func roleTitle(_ role: ModelRole) -> String {
        let resolved = ModelRoleResolver.resolve(role.name, in: workspaceStateModel.roles)
        let modelName = resolved?.qualifiedId.map { qualifiedId in
            session.availableModels.first { $0.qualifiedId == qualifiedId }?.name ?? qualifiedId
        } ?? ""
        let effort = resolved?.effort.map { " :\($0)" } ?? ""
        return "\(role.displayName) (\(role.name)) · \(modelName)\(effort)"
    }

    private func isCurrent(_ role: ModelRole) -> Bool {
        activeRole?.name == role.name
    }

    /// Levels the current model can actually use, per its catalog entry.
    private var supportedLevels: [ThinkingLevel] {
        guard let model = session.currentModel else { return ThinkingLevel.allCases }
        guard model.reasoning == true else { return [.off] }
        guard let efforts = model.thinking?.efforts, !efforts.isEmpty else { return ThinkingLevel.allCases }
        return [.off] + ThinkingLevel.allCases.filter { efforts.contains($0.rawValue) }
    }

    private var thinkingControl: some View {
        Menu {
            ForEach(ThinkingLevel.allCases) { level in
                Button {
                    session.select(thinkingLevel: level)
                } label: {
                    if session.thinkingLevel == level {
                        Label(level.title, systemImage: "checkmark")
                    } else {
                        Text(level.title)
                    }
                }
                .disabled(!supportedLevels.contains(level))
            }
        } label: {
            StatusPill(
                title: session.thinkingLevel?.title ?? "Thinking",
                systemImage: "brain",
                tint: .purple
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Thinking level for the current model")
        .disabled(session.status != .ready)
    }

    private var statusText: some View {
        Group {
            switch session.status {
            case .launching:
                Label("Starting", systemImage: "hourglass")
            case .ready:
                if session.isStreaming {
                    Label("Working", systemImage: "circle.fill")
                        .foregroundStyle(Color.accentColor)
                } else {
                    Label("Idle", systemImage: "circle")
                }
            case .exited(let code):
                Label("Exited (\(code))", systemImage: "power")
            case .failed:
                Label("Failed", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

#Preview {
    ChatStatusBar(session: .preview)
        .frame(width: 700)
}
