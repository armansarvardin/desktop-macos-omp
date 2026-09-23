//
//  Chat.swift
//  OhMyPi
//
//  Created by Arman Sarvardin on 22/9/26.
//

import SwiftUI

/// Conversation screen for one live session: transcript, composer and status.
struct Chat: View {
    @Environment(WorkspaceStateModel.self) private var workspaceStateModel

    let session: AgentSessionStateModel

    @AppStorage(.AppStorageKey.showThinking)
    private var showThinking = true

    @State private var isModelPickerPresented = false

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: .zero) {
            Transcript(session: session, showThinking: showThinking)

            Divider()

            Composer(session: session)

            ChatStatusBar(session: session)
        }
        .overlay(alignment: .top) {
            banners
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                toolbarContent
            }
        }
        .sheet(isPresented: $isModelPickerPresented) {
            ModelPicker(session: session)
        }
        .extensionUIRequests(for: session)
        .onDisappear {
            if !session.status.isAlive {
                workspaceStateModel.refreshSessions(for: session.projectURL)
            }
        }
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var toolbarContent: some View {
        Button {
            isModelPickerPresented = true
        } label: {
            Label(session.currentModel?.name ?? "Model", systemImage: "cpu")
        }
        .help("Change model")
        .disabled(session.status != .ready)

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
            }

            Divider()

            Toggle("Show thinking", isOn: $showThinking)
        } label: {
            Label(session.thinkingLevel?.title ?? "Thinking", systemImage: "brain")
        }
        .help("Thinking level")
        .disabled(session.status != .ready)

        Menu {
            Button("New Session in Project", systemImage: "plus.bubble") {
                workspaceStateModel.newSession(in: session.projectURL)
            }
            Button("Cycle Model", systemImage: "arrow.triangle.2.circlepath") {
                session.cycleModel()
            }
            .keyboardShortcut("m", modifiers: [.command, .control])
            .disabled(session.status != .ready)
            Button("Models & Providers…", systemImage: "slider.horizontal.3") {
                openWindow(id: WindowID.modelRoles)
            }
            Button("Compact Context", systemImage: "arrow.down.right.and.arrow.up.left") {
                session.compact()
            }
            .disabled(session.status != .ready || session.isStreaming)

            Button(session.state?.fastModeEnabled == true ? "Disable Fast Mode" : "Enable Fast Mode", systemImage: "hare") {
                session.toggleFastMode()
            }
            .disabled(session.status != .ready)

            Divider()

            if let fileURL = session.sessionFileURL {
                Button("Reveal Session File", systemImage: "doc.text.magnifyingglass") {
                    NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                }
            }
            Button("Reveal Project in Finder", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([session.projectURL])
            }

            Divider()

            Button("Close Session", systemImage: "xmark.circle", role: .destructive) {
                workspaceStateModel.close(session)
            }
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
    }

    // MARK: - Banners

    private var banners: some View {
        VStack(spacing: 6) {
            ForEach(session.banners) { banner in
                HStack(spacing: 8) {
                    Image(systemName: bannerIcon(for: banner.level))
                    Text(verbatim: banner.message)
                        .lineLimit(3)
                    Spacer(minLength: 0)
                    Button {
                        session.dismissBanner(banner)
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                }
                .font(.callout)
                .padding(10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(bannerTint(for: banner.level).opacity(0.5))
                }
                .frame(maxWidth: 520)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.top, 8)
        .animation(.snappy(duration: 0.25), value: session.banners)
    }

    private func bannerIcon(for level: Notice.Level) -> String {
        switch level {
        case .info: "info.circle"
        case .warning: "exclamationmark.triangle"
        case .error: "xmark.octagon"
        }
    }

    private func bannerTint(for level: Notice.Level) -> Color {
        switch level {
        case .info: .accentColor
        case .warning: .orange
        case .error: .red
        }
    }
}

#Preview {
    Chat(session: .preview)
        .withPreviewEnvironment()
        .frame(width: 760, height: 600)
}
