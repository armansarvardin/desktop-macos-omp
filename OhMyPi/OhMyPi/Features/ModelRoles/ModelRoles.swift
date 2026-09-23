//
//  ModelRoles.swift
//  OhMyPi
//
//  Created by Arman Sarvardin on 22/9/26.
//

import SwiftUI

/// Window for assigning models to roles, tagging custom roles and ordering the
/// model cycle. Writes go through `omp config set`, so they apply to new sessions.
struct ModelRoles: View {
    @Environment(WorkspaceStateModel.self) private var workspaceStateModel
    @Environment(\.ompConfigClient) private var configClient
    @Environment(\.rpcLauncher) private var rpcLauncher

    @State private var modelRolesStateModel: ModelRolesStateModel?
    @State private var newRoleName = ""
    @State private var pickerRole: ModelRole?

    var body: some View {
        Group {
            if let modelRolesStateModel {
                content(modelRolesStateModel)
            } else {
                ProgressView()
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .task {
            guard modelRolesStateModel == nil else { return }
            let model = ModelRolesStateModel(configClient: configClient, launcher: rpcLauncher)
            modelRolesStateModel = model
            await model.load()
            await model.loadModels(preferring: workspaceStateModel.openSessions.first { !$0.availableModels.isEmpty }?.availableModels ?? [])
        }
    }

    // MARK: - Content

    private func content(_ model: ModelRolesStateModel) -> some View {
        VStack(spacing: .zero) {
            List {
                Section {
                    ForEach(model.builtInRoles) { role in
                        ModelRoleRow(role: role, model: model) {
                            pickerRole = role
                        }
                    }
                } header: {
                    Text("Built-in roles")
                } footer: {
                    Text("Roles resolve `@name` aliases in settings and CLI flags such as `--model smol`. An effort suffix pins the thinking level for that role.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    ForEach(model.customRoles) { role in
                        ModelRoleRow(role: role, model: model) {
                            pickerRole = role
                        }
                        .contextMenu {
                            Button("Remove Role", role: .destructive) {
                                model.removeRole(named: role.name)
                            }
                        }
                    }

                    HStack {
                        TextField("New role name", text: $newRoleName)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(addRole)
                        Button("Add", action: addRole)
                            .disabled(newRoleName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("Custom roles")
                } footer: {
                    Text("Custom roles appear as tags in the model selector and can be included in the cycle.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    ForEach(Array(model.cycleRoles.enumerated()), id: \.offset) { _, role in
                        HStack {
                            Image(systemName: "line.3.horizontal")
                                .foregroundStyle(.tertiary)
                            Text(verbatim: role.displayName)
                            Text(verbatim: role.selector.rawValue)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .onMove { source, destination in
                        model.moveInCycle(from: source, to: destination)
                    }
                } header: {
                    Text("Cycle order")
                } footer: {
                    Text("Order used by `/model` cycling in the CLI and by Cycle Model in the app. Drag to reorder; toggle the cycle checkbox on a role to include it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.inset)

            Divider()

            footer(model)
        }
        .sheet(item: $pickerRole) { role in
            ModelCatalogPicker(
                models: model.availableModels,
                isLoading: model.isLoadingModels,
                selectedQualifiedId: role.selector.qualifiedId
            ) { chosen in
                model.assign(.model(qualifiedId: chosen.qualifiedId, effort: role.selector.effort), to: role.name)
            }
        }
    }

    private func footer(_ model: ModelRolesStateModel) -> some View {
        HStack(spacing: 12) {
            switch model.phase {
            case .idle:
                if let savedAt = model.lastSavedAt {
                    Label("Saved \(savedAt.formatted(date: .omitted, time: .shortened)). Applies to new sessions.", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Changes apply to sessions started after saving.")
                        .foregroundStyle(.secondary)
                }
            case .loading:
                ProgressView().controlSize(.small)
                Text("Reading config…").foregroundStyle(.secondary)
            case .saving:
                ProgressView().controlSize(.small)
                Text("Writing config…").foregroundStyle(.secondary)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            Spacer()

            Button("Reload") {
                Task { await model.load() }
            }

            Button("Discard") {
                model.discardChanges()
            }
            .disabled(!model.hasChanges)

            Button("Save") {
                Task {
                    await model.save()
                    await workspaceStateModel.reloadRoles()
                }
            }
            .keyboardShortcut("s", modifiers: .command)
            .buttonStyle(.borderedProminent)
            .disabled(!model.hasChanges || model.phase == .saving)
        }
        .font(.callout)
        .padding(12)
        .background(.bar)
    }

    private func addRole() {
        modelRolesStateModel?.addRole(named: newRoleName)
        newRoleName = ""
    }
}

#Preview {
    ModelRoles()
        .withPreviewEnvironment()
}
