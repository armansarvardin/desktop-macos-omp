//
//  CodeBlock.swift
//  OhMyPi
//
//  Created by Arman Sarvardin on 22/9/26.
//

import AppKit
import SwiftUI

/// Monospaced block with a language tag and a copy button.
struct CodeBlock: View {
    var language: String?
    let code: String
    var maxHeight: CGFloat? = nil

    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: .zero) {
            HStack {
                Text(verbatim: language ?? "text")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    didCopy = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        didCopy = false
                    }
                } label: {
                    Label(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.5))

            ScrollView(.horizontal) {
                Text(verbatim: code)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: maxHeight)
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
    }
}

#Preview {
    CodeBlock(language: "swift", code: "let answer = 42\nprint(answer)")
        .padding()
        .frame(width: 400)
}
