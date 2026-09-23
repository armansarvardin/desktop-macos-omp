//
//  ToolCallCard.swift
//  OhMyPi
//
//  Created by Arman Sarvardin on 22/9/26.
//

import SwiftUI

/// One tool invocation: header with status, expandable arguments and output.
struct ToolCallCard: View {
    let call: ToolCallState

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: .zero) {
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                header
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                details
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(borderColor, lineWidth: 1)
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(spacing: 8) {
            statusIcon
                .frame(width: 14)

            Text(verbatim: call.name)
                .font(.system(.callout, design: .monospaced))
                .fontWeight(.semibold)

            Text(verbatim: call.summary)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch call.status {
        case .pending:
            Image(systemName: "circle.dotted")
                .foregroundStyle(.tertiary)
        case .running:
            ProgressView()
                .controlSize(.mini)
        case .succeeded:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let arguments = call.arguments.objectValue, !arguments.isEmpty {
                Text("Arguments")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                CodeBlock(language: "json", code: call.arguments.prettyPrinted, maxHeight: 240)
            }

            if !call.resultText.isEmpty {
                Text(call.status == .failed ? "Error" : "Result")
                    .font(.caption)
                    .foregroundStyle(call.status == .failed ? .red : .secondary)
                CodeBlock(language: nil, code: call.resultText, maxHeight: 360)
            }

            if call.resultImageCount > 0 {
                StatusPill(title: "\(call.resultImageCount) image(s) returned", systemImage: "photo")
            }
        }
        .padding(10)
    }

    private var borderColor: Color {
        switch call.status {
        case .failed: .red.opacity(0.4)
        default: Color(nsColor: .separatorColor)
        }
    }
}

#Preview {
    VStack(spacing: 8) {
        ToolCallCard(
            call: ToolCallState(
                id: "1", name: "bash", arguments: ["cmd": "swift build"],
                status: .running, resultText: "", resultImageCount: 0
            )
        )
        ToolCallCard(
            call: ToolCallState(
                id: "2", name: "read", arguments: ["path": "Sources/App/main.swift"],
                status: .failed, resultText: "ENOENT: no such file", resultImageCount: 0
            )
        )
    }
    .padding()
    .frame(width: 520)
}
