//
//  MarkdownText.swift
//  OhMyPi
//
//  Created by Arman Sarvardin on 22/9/26.
//

import SwiftUI

/// Renders block-level markdown natively: paragraphs, headings, lists,
/// quotes, rules and code fences.
struct MarkdownText: View {
    let markdown: String

    private var blocks: [MarkdownBlock] {
        MarkdownBlock.parse(markdown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let text):
            InlineMarkdown(text: text)

        case .heading(let level, let text):
            InlineMarkdown(text: text)
                .font(headingFont(level: level))
                .fontWeight(.semibold)
                .padding(.top, 4)

        case .code(let language, let code):
            CodeBlock(language: language, code: code)

        case .list(let ordered, let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: ordered ? "\(index + 1)." : "•")
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 14, alignment: .trailing)
                        InlineMarkdown(text: item)
                    }
                }
            }

        case .quote(let text):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(.tertiary)
                    .frame(width: 3)
                InlineMarkdown(text: text)
                    .foregroundStyle(.secondary)
            }

        case .rule:
            Divider()
        }
    }

    private func headingFont(level: Int) -> Font {
        switch level {
        case 1: .title2
        case 2: .title3
        default: .headline
        }
    }
}

/// Inline markdown (bold, italics, code, links) with a plain-text fallback.
struct InlineMarkdown: View {
    let text: String

    var body: some View {
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attributed)
        } else {
            Text(verbatim: text)
        }
    }
}

#Preview {
    MarkdownText(
        markdown: """
        # Heading

        Some **bold** and `inline code` text.

        - first
        - second

        1. one
        2. two

        > a quote

        ```swift
        let answer = 42
        ```
        """
    )
    .padding()
    .frame(width: 420)
}
