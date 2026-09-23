//
//  ThinkingBlock.swift
//  OhMyPi
//
//  Created by Arman Sarvardin on 22/9/26.
//

import SwiftUI

/// Collapsible reasoning trace.
struct ThinkingBlock: View {
    let text: String
    let isStreaming: Bool

    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Text(verbatim: text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "brain")
                Text(isStreaming ? "Thinking…" : "Thought process")
                if !isExpanded {
                    Text(verbatim: text.split(separator: "\n").first.map(String.init) ?? "")
                        .lineLimit(1)
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    ThinkingBlock(text: "First I need to inspect the repository.\nThen run the tests.", isStreaming: false)
        .padding()
        .frame(width: 500)
}
