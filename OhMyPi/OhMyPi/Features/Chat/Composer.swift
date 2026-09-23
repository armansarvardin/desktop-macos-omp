//
//  Composer.swift
//  OhMyPi
//
//  Created by Arman Sarvardin on 22/9/26.
//

import SwiftUI

/// Prompt editor. Return sends, Shift+Return inserts a newline.
struct Composer: View {
    @Bindable var session: AgentSessionStateModel

    @FocusState private var isFocused: Bool
    @State private var selectedSuggestionIndex = 0

    private var suggestions: [SlashSuggestion] {
        session.slashSuggestions ?? []
    }

    private var isPaletteVisible: Bool {
        !suggestions.isEmpty && session.status == .ready
    }

    var body: some View {
        VStack(spacing: 8) {
            if isPaletteVisible {
                SlashCommandPalette(
                    suggestions: suggestions,
                    selectedIndex: selectedSuggestionIndex
                ) { suggestion in
                    session.accept(suggestion)
                }
                .transition(.opacity)
            }

            TextEditor(text: $session.draft)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 44, maxHeight: 180)
                .fixedSize(horizontal: false, vertical: true)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isFocused ? Color.accentColor.opacity(0.6) : Color(nsColor: .separatorColor))
                }
                .overlay(alignment: .topLeading) {
                    if session.draft.isEmpty {
                        Text(placeholder)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
                .focused($isFocused)
                .onKeyPress(.return, phases: .down) { press in
                    guard !press.modifiers.contains(.shift) else { return .ignored }
                    if isPaletteVisible, let suggestion = selectedSuggestion {
                        session.accept(suggestion)
                        return .handled
                    }
                    guard session.canSend else { return .ignored }
                    session.sendDraft()
                    return .handled
                }
                .onKeyPress(.tab, phases: .down) { _ in
                    guard isPaletteVisible, let suggestion = selectedSuggestion else { return .ignored }
                    session.draft = suggestion.completion
                    return .handled
                }
                .onKeyPress(.upArrow, phases: .down) { _ in
                    guard isPaletteVisible else { return .ignored }
                    selectedSuggestionIndex = max(0, selectedSuggestionIndex - 1)
                    return .handled
                }
                .onKeyPress(.downArrow, phases: .down) { _ in
                    guard isPaletteVisible else { return .ignored }
                    selectedSuggestionIndex = min(suggestions.count - 1, selectedSuggestionIndex + 1)
                    return .handled
                }
                .onKeyPress(.escape, phases: .down) { _ in
                    guard isPaletteVisible else { return .ignored }
                    session.draft = ""
                    return .handled
                }
                .onChange(of: session.draft) {
                    selectedSuggestionIndex = 0
                }
                .disabled(!session.status.isAlive)

            HStack {
                Text(hintText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Spacer()

                if session.isStreaming {
                    Button("Queue", systemImage: "text.badge.plus") {
                        session.queueFollowUp()
                    }
                    .help("Send after the current turn finishes")
                    .disabled(!session.canSend)

                    Button("Stop", systemImage: "stop.fill", role: .destructive) {
                        session.abort()
                    }
                    .keyboardShortcut(".", modifiers: .command)
                }

                Button(session.isStreaming ? "Steer" : "Send", systemImage: "paperplane.fill") {
                    session.sendDraft()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!session.canSend)
            }
            .controlSize(.small)
        }
        .padding(12)
        .animation(.snappy(duration: 0.15), value: isPaletteVisible)
        .onAppear {
            isFocused = true
        }
    }

    private var selectedSuggestion: SlashSuggestion? {
        suggestions.indices.contains(selectedSuggestionIndex) ? suggestions[selectedSuggestionIndex] : nil
    }

    private var hintText: LocalizedStringKey {
        if isPaletteVisible {
            "↑↓ to choose, Tab to complete, Return to run, Esc to clear"
        } else if session.isStreaming {
            "Return steers the running turn, / for commands"
        } else {
            "Return to send, Shift+Return for a new line, / for commands"
        }
    }

    private var placeholder: String {
        switch session.status {
        case .launching: "Starting oh-my-pi…"
        case .ready: "Ask oh-my-pi to do something in \(session.projectName)"
        case .exited: "The agent process has exited"
        case .failed: "The agent could not be started"
        }
    }
}

#Preview {
    Composer(session: .preview)
        .frame(width: 600)
}
