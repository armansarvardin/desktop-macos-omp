//
//  ProviderModelsSheet.swift
//  OhMyPi
//
//  Created by Arman Sarvardin on 23/9/26.
//

import SwiftUI

/// Choose which of a provider's models the CLI may offer (`enabledModels`).
struct ProviderModelsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let providerId: String
    let model: ProvidersStateModel

    @State private var query = ""

    private var provider: ProviderStatus? {
        model.provider(providerId)
    }

    private var allSelected: Binding<Bool> {
        Binding(
            get: { provider?.scope == .all },
            set: { model.setScope($0 ? .all : .selected([]), for: providerId) }
        )
    }

    var body: some View {
        VStack(spacing: .zero) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: provider?.name ?? providerId)
                        .font(.headline)
                    Text("Unchecked models are hidden from the model picker and role assignments.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)

            HStack {
                Toggle("All models", isOn: allSelected)
                    .toggleStyle(.checkbox)
                TextField("Filter", text: $query)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            Divider()

            List(filteredModels) { entry in
                Toggle(isOn: binding(for: entry)) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: entry.name)
                            Text(verbatim: entry.id)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let contextWindow = entry.contextWindow {
                            StatusPill(title: "\(contextWindow / 1_000)k ctx", systemImage: "square.stack")
                        }
                        if entry.reasoning == true {
                            StatusPill(title: "reasoning", systemImage: "brain", tint: .purple)
                        }
                    }
                }
                .toggleStyle(.checkbox)
            }
            .listStyle(.inset)
        }
        .frame(width: 600, height: 520)
    }

    private var filteredModels: [RpcModel] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        let models = provider?.models ?? []
        guard !needle.isEmpty else { return models }
        return models.filter { $0.id.lowercased().contains(needle) || $0.name.lowercased().contains(needle) }
    }

    private func binding(for entry: RpcModel) -> Binding<Bool> {
        Binding(
            get: {
                switch provider?.scope {
                case .all: true
                case .selected(let ids): ids.contains(entry.id)
                case nil: false
                }
            },
            set: { model.setModel(entry.id, enabled: $0, for: providerId) }
        )
    }
}
