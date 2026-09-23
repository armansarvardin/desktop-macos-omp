//
//  ModelPicker.swift
//  OhMyPi
//
//  Created by Arman Sarvardin on 22/9/26.
//

import SwiftUI

/// Searchable list of every model the CLI can route to.
struct ModelPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WorkspaceStateModel.self) private var workspaceStateModel

    let session: AgentSessionStateModel

    @State private var query = ""

    private var filteredModels: [RpcModel] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return session.availableModels }

        return session.availableModels.filter { model in
            model.qualifiedId.lowercased().contains(needle) || model.name.lowercased().contains(needle)
        }
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

                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(12)

            Divider()

            if session.availableModels.isEmpty {
                ProgressView("Loading models…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if query.isEmpty, !workspaceStateModel.switchableRoles.isEmpty {
                        Section("Roles") {
                            ForEach(workspaceStateModel.switchableRoles) { role in
                                roleRow(role)
                            }
                        }
                    }

                    ForEach(groupedModels, id: \.provider) { group in
                        Section(group.provider) {
                            ForEach(group.models) { model in
                                modelRow(model)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(width: 560, height: 520)
        .task {
            await session.loadAvailableModels()
        }
    }

    /// A configured role: switching applies its model and effort suffix.
    private func roleRow(_ role: ModelRole) -> some View {
        let resolved = ModelRoleResolver.resolve(role.name, in: workspaceStateModel.roles)
        let model = resolved?.qualifiedId.flatMap { id in session.availableModels.first { $0.qualifiedId == id } }
        let isCurrent = session.activeRole(in: workspaceStateModel.roles)?.name == role.name

        return Button {
            session.select(role: role, in: workspaceStateModel.roles)
            dismiss()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isCurrent ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary.opacity(0.4))

                StatusPill(title: role.name, tint: roleTint(role))
                    .frame(width: 84, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: role.displayName)
                    Text(verbatim: model?.name ?? resolved?.qualifiedId ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let effort = resolved?.effort {
                    StatusPill(title: effort, systemImage: "brain", tint: .purple)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func roleTint(_ role: ModelRole) -> Color {
        switch role.color {
        case "accent": .accentColor
        case "success": .green
        case "warning": .orange
        case "error": .red
        case "info": .blue
        default: .secondary
        }
    }

    private func modelRow(_ model: RpcModel) -> some View {
        Button {
            session.select(model: model)
            dismiss()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: session.currentModel?.qualifiedId == model.qualifiedId ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(session.currentModel?.qualifiedId == model.qualifiedId ? Color.accentColor : Color.secondary.opacity(0.4))

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
                if model.supportsImages {
                    StatusPill(title: "vision", systemImage: "eye")
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ModelPicker(session: .preview)
        .withPreviewEnvironment()
}
