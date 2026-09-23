//
//  AssistantMessageRow.swift
//  OhMyPi
//
//  Created by Arman Sarvardin on 22/9/26.
//

import SwiftUI

struct AssistantMessageRow: View {
    let content: AssistantContent
    let showThinking: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkle")
                .font(.callout)
                .foregroundStyle(Color.accentColor)
                .frame(width: 20, height: 20)
                .background(Color.accentColor.opacity(0.12), in: Circle())
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(content.blocks) { block in
                    blockView(block)
                }

                if let errorMessage = content.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.red)
                }

                if content.isStreaming, !content.hasVisibleContent {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func blockView(_ block: AssistantBlock) -> some View {
        switch block.kind {
        case .text(let text):
            if !text.isEmpty {
                MarkdownText(markdown: text)
            }

        case .thinking(let thinking):
            if showThinking, !thinking.isEmpty {
                ThinkingBlock(text: thinking, isStreaming: content.isStreaming)
            }

        case .toolCall(let call):
            ToolCallCard(call: call)

        case .image(let mimeType):
            StatusPill(title: "Generated image (\(mimeType))", systemImage: "photo")
        }
    }
}

#Preview {
    AssistantMessageRow(
        content: AssistantContent(
            blocks: [
                AssistantBlock(id: "1", kind: .thinking("Let me look at the file first.")),
                AssistantBlock(
                    id: "2",
                    kind: .toolCall(
                        ToolCallState(
                            id: "c1", name: "bash", arguments: ["cmd": "ls -la"],
                            status: .succeeded, resultText: "total 0\ndrwxr-xr-x  2 user  staff  64 Jan  1 00:00 .",
                            resultImageCount: 0
                        )
                    )
                ),
                AssistantBlock(id: "3", kind: .text("Here is what I found:\n\n- one\n- two"))
            ],
            model: "claude-fable-5-1",
            isStreaming: false,
            errorMessage: nil
        ),
        showThinking: true
    )
    .padding()
    .frame(width: 600)
}
