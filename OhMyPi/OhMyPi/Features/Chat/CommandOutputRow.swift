//
//  CommandOutputRow.swift
//  OhMyPi
//
//  Created by Arman Sarvardin on 22/9/26.
//

import SwiftUI

/// Plain-text result of a builtin slash command such as `/context` or `/model`.
struct CommandOutputRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "terminal")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .padding(.top, 2)

            Text(verbatim: text)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

#Preview {
    CommandOutputRow(text: "Current model: openrouter/moonshotai/kimi-k3\nFast mode is off.")
        .padding()
        .frame(width: 520)
}
