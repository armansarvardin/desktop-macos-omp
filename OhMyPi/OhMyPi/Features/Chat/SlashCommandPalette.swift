//
//  SlashCommandPalette.swift
//  OhMyPi
//
//  Created by Arman Sarvardin on 22/9/26.
//

import SwiftUI

/// Popover-style list shown above the composer while a `/command` is typed.
struct SlashCommandPalette: View {
    let suggestions: [SlashSuggestion]
    let selectedIndex: Int
    let onSelect: (SlashSuggestion) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                        row(suggestion, isSelected: index == selectedIndex)
                            .id(suggestion.id)
                            .onTapGesture {
                                onSelect(suggestion)
                            }
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 280)
            .onChange(of: selectedIndex, initial: true) {
                guard suggestions.indices.contains(selectedIndex) else { return }
                proxy.scrollTo(suggestions[selectedIndex].id, anchor: .center)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(nsColor: .separatorColor))
        }
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
    }

    // MARK: - Subviews

    private func row(_ suggestion: SlashSuggestion, isSelected: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verbatim: suggestion.title)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)
                .lineLimit(1)

            if let hint = suggestion.hint {
                Text(verbatim: hint)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            if let detail = suggestion.detail {
                Text(verbatim: detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            if let source = suggestion.source, source != "builtin" {
                StatusPill(title: source)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
    }
}

#Preview {
    SlashCommandPalette(
        suggestions: [
            SlashSuggestion(id: "1", title: "/model", detail: "Show current model selection", hint: nil, source: "builtin", completion: "/model", expectsInput: false),
            SlashSuggestion(id: "2", title: "/fast", detail: "Toggle fast mode", hint: "[on|off|status]", source: "builtin", completion: "/fast ", expectsInput: true),
            SlashSuggestion(id: "3", title: "/skill:swiftui-patterns", detail: "Builds SwiftUI views with modern MV architecture", hint: "arguments", source: "skill", completion: "/skill:swiftui-patterns ", expectsInput: true)
        ],
        selectedIndex: 1,
        onSelect: { _ in }
    )
    .padding()
    .frame(width: 620)
}
