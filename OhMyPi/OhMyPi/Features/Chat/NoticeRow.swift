//
//  NoticeRow.swift
//  OhMyPi
//
//  Created by Arman Sarvardin on 22/9/26.
//

import SwiftUI

struct NoticeRow: View {
    let notice: Notice

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: notice.message)
                    .font(.callout)
                    .textSelection(.enabled)

                if let source = notice.source {
                    Text(verbatim: source)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
        .padding(10)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var icon: String {
        switch notice.level {
        case .info: "info.circle"
        case .warning: "exclamationmark.triangle"
        case .error: "xmark.octagon"
        }
    }

    private var tint: Color {
        switch notice.level {
        case .info: .secondary
        case .warning: .orange
        case .error: .red
        }
    }
}

#Preview {
    VStack {
        NoticeRow(notice: Notice(level: .info, message: "Context compacted.", source: nil))
        NoticeRow(notice: Notice(level: .error, message: "Provider returned 429", source: "openrouter"))
    }
    .padding()
    .frame(width: 500)
}
