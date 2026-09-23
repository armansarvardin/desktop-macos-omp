//
//  SessionRow.swift
//  OhMyPi
//
//  Created by Arman Sarvardin on 22/9/26.
//

import SwiftUI

struct SessionRow: View {
    let title: String
    let subtitle: String
    let isLive: Bool
    let isStreaming: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isLive ? "bubble.left.and.text.bubble.right.fill" : "clock")
                .foregroundStyle(isLive ? Color.accentColor : .secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .lineLimit(1)

                Text(verbatim: subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if isStreaming {
                ProgressView()
                    .controlSize(.mini)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    List {
        SessionRow(title: "Fix the login bug", subtitle: "Working…", isLive: true, isStreaming: true)
        SessionRow(title: "Refactor networking", subtitle: "2 days ago", isLive: false, isStreaming: false)
    }
    .frame(width: 260)
}
