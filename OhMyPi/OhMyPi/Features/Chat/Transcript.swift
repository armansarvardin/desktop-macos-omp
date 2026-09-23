//
//  Transcript.swift
//  OhMyPi
//
//  Created by Arman Sarvardin on 22/9/26.
//

import SwiftUI

/// Scrolling list of transcript rows that follows the newest content.
struct Transcript: View {
    let session: AgentSessionStateModel
    let showThinking: Bool

    @State private var isPinnedToBottom = true

    private let bottomAnchor = "transcript-bottom"

    private struct ScrollSnapshot: Equatable {
        var offsetY: CGFloat
        var isAtBottom: Bool
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if session.transcript.isEmpty {
                        emptyState
                    }

                    ForEach(session.transcript) { item in
                        row(for: item)
                    }

                    if session.isStreaming, !hasStreamingAssistant {
                        workingIndicator
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(bottomAnchor)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: session.transcript) {
                guard isPinnedToBottom else { return }
                proxy.scrollTo(bottomAnchor, anchor: .bottom)
            }
            .onAppear {
                proxy.scrollTo(bottomAnchor, anchor: .bottom)
            }
            .overlay(alignment: .bottomTrailing) {
                if !isPinnedToBottom {
                    Button {
                        isPinnedToBottom = true
                        withAnimation(.smooth(duration: 0.3)) {
                            proxy.scrollTo(bottomAnchor, anchor: .bottom)
                        }
                    } label: {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(12)
                }
            }
            .onScrollGeometryChange(for: ScrollSnapshot.self) { geometry in
                ScrollSnapshot(
                    offsetY: geometry.contentOffset.y,
                    isAtBottom: geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 40
                )
            } action: { previous, current in
                if current.isAtBottom {
                    isPinnedToBottom = true
                } else if current.offsetY < previous.offsetY - 1 {
                    // Content growing does not move the offset; only a real scroll up unpins.
                    isPinnedToBottom = false
                }
            }
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(for item: TranscriptItem) -> some View {
        switch item.kind {
        case .user(let user):
            UserMessageRow(content: user, timestamp: item.timestamp)

        case .assistant(let assistant):
            AssistantMessageRow(content: assistant, showThinking: showThinking)

        case .notice(let notice):
            NoticeRow(notice: notice)

        case .compaction(let summary):
            NoticeRow(
                notice: Notice(level: .info, message: "Context compacted: \(summary)", source: nil)
            )

        case .commandOutput(let text):
            CommandOutputRow(text: text)
        }
    }

    private var hasStreamingAssistant: Bool {
        if case .assistant(let content) = session.transcript.last?.kind {
            content.isStreaming && content.hasVisibleContent
        } else {
            false
        }
    }

    private var workingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Thinking…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 4)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch session.status {
            case .launching:
                Label("Starting oh-my-pi…", systemImage: "hourglass")
            case .ready:
                if session.isLoadingHistory {
                    Label("Loading history…", systemImage: "clock.arrow.circlepath")
                } else {
                    Label("Ready. Ask something about \(session.projectName).", systemImage: "sparkles")
                }
            case .exited(let code):
                Label("The agent process exited (code \(code)).", systemImage: "power")
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.top, 40)
    }
}

#Preview {
    Transcript(session: .preview, showThinking: true)
        .frame(width: 700, height: 500)
}
