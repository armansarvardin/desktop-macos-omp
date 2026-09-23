//
//  StatusPill.swift
//  OhMyPi
//
//  Created by Arman Sarvardin on 22/9/26.
//

import SwiftUI

/// Small capsule used for model names, thinking level and context usage.
struct StatusPill: View {
    let title: String
    var systemImage: String? = nil
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2)
            }
            Text(verbatim: title)
                .font(.caption)
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

#Preview {
    HStack {
        StatusPill(title: "Claude Fable 5.1", systemImage: "cpu")
        StatusPill(title: "high", systemImage: "brain", tint: .purple)
        StatusPill(title: "12%", systemImage: "gauge", tint: .green)
    }
    .padding()
}
