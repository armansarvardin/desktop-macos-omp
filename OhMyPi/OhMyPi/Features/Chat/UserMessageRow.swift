//
//  UserMessageRow.swift
//  OhMyPi
//
//  Created by Arman Sarvardin on 22/9/26.
//

import SwiftUI

struct UserMessageRow: View {
    let content: UserContent
    let timestamp: Date

    var body: some View {
        HStack(alignment: .top) {
            Spacer(minLength: 80)

            VStack(alignment: .trailing, spacing: 4) {
                Text(verbatim: content.text)
                    .font(content.isCommand ? .system(.body, design: .monospaced) : .body)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.accentColor.opacity(content.isPending ? 0.10 : 0.16))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                HStack(spacing: 6) {
                    if content.isSteering {
                        StatusPill(title: "steer", systemImage: "arrow.turn.down.right", tint: .orange)
                    }
                    if content.imageCount > 0 {
                        StatusPill(title: "\(content.imageCount) image(s)", systemImage: "photo")
                    }
                    Text(timestamp, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

#Preview {
    VStack {
        UserMessageRow(
            content: UserContent(text: "Please fix the failing test.", imageCount: 0, isSteering: false, isPending: false),
            timestamp: .now
        )
        UserMessageRow(
            content: UserContent(text: "Actually, skip the docs.", imageCount: 1, isSteering: true, isPending: true),
            timestamp: .now
        )
    }
    .padding()
    .frame(width: 500)
}
