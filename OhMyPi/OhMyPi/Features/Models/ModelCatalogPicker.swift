//
//  ModelCatalogPicker.swift
//  OhMyPi
//
//  Created by Arman Sarvardin on 22/9/26.
//

import SwiftUI

/// Searchable, provider-grouped model list independent of any session.
struct ModelCatalogPicker: View {
    @Environment(\.dismiss) private var dismiss

    let models: [RpcModel]
    let isLoading: Bool
    let selectedQualifiedId: String?
    let onSelect: (RpcModel) -> Void

    @State private var query = ""

    private var filteredModels: [RpcModel] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return models }
        return models.filter { $0.qualifiedId.lowercased().contains(needle) || $0.name.lowercased().contains(needle) }
    }

    private var groupedModels: [(provider: String, models: [RpcModel])] {
        Dictionary(grouping: filteredModels, by: \.provider)
            .map { (provider: $0.key, models: $0.value) }
            .sorted { $0.provider < $1.provider }
    }

    var body: some View {
        VStack(spacing: .zero) {
            HStack {
                TextField("Search models", text: $query)
                    .textFieldStyle(.roundedBorder)
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)

            Divider()

            if models.isEmpty {
                if isLoading {
                    ProgressView("Loading model catalog…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView("No models", systemImage: "cpu", description: Text("The catalog could not be loaded."))
                }
            } else {
                List {
                    ForEach(groupedModels, id: \.provider) { group in
                        Section(group.provider) {
                            ForEach(group.models) { model in
                                row(model)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(width: 560, height: 520)
    }

    private func row(_ model: RpcModel) -> some View {
        Button {
            onSelect(model)
            dismiss()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selectedQualifiedId == model.qualifiedId ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedQualifiedId == model.qualifiedId ? Color.accentColor : Color.secondary.opacity(0.4))

                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: model.name)
                    Text(verbatim: model.id)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let contextWindow = model.contextWindow {
                    StatusPill(title: "\(contextWindow / 1_000)k ctx", systemImage: "square.stack")
                }
                if model.reasoning == true {
                    StatusPill(title: "reasoning", systemImage: "brain", tint: .purple)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
