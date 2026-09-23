//
//  ModelRoleRow.swift
//  OhMyPi
//
//  Created by Arman Sarvardin on 22/9/26.
//

import SwiftUI

/// One role: tag, model button, effort picker, cycle toggle.
struct ModelRoleRow: View {
    let role: ModelRole
    let model: ModelRolesStateModel
    let onPickModel: () -> Void

    private var effortBinding: Binding<String> {
        Binding(
            get: { role.selector.effort ?? "" },
            set: { model.setEffort($0.isEmpty ? nil : $0, for: role.name) }
        )
    }

    private var cycleBinding: Binding<Bool> {
        Binding(
            get: { role.isInCycle },
            set: { model.setInCycle($0, for: role.name) }
        )
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    StatusPill(title: role.name, tint: tint)
                    Text(verbatim: role.displayName)
                        .fontWeight(.medium)
                }
                if let description = role.description {
                    Text(verbatim: description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: 260, alignment: .leading)

            Button(action: onPickModel) {
                HStack(spacing: 6) {
                    Image(systemName: "cpu")
                    Text(verbatim: modelTitle)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .help(role.selector.rawValue)

            Picker("Effort", selection: effortBinding) {
                Text("Inherit").tag("")
                ForEach(ModelSelector.efforts, id: \.self) { effort in
                    Text(verbatim: effort).tag(effort)
                }
            }
            .labelsHidden()
            .frame(width: 96)
            .disabled(role.selector.qualifiedId == nil)

            if !role.isBuiltIn {
                tagEditor
            }

            Toggle("Cycle", isOn: cycleBinding)
                .toggleStyle(.checkbox)
                .help("Include in the model cycle")
        }
        .padding(.vertical, 2)
    }

    // MARK: - Subviews

    private var tagEditor: some View {
        Menu {
            ForEach(ModelTag.colors, id: \.self) { color in
                Button {
                    model.setTag(ModelTag(name: role.tag?.name ?? role.name, color: color, hidden: role.tag?.hidden ?? false), for: role.name)
                } label: {
                    if role.color == color {
                        Label(color, systemImage: "checkmark")
                    } else {
                        Text(verbatim: color)
                    }
                }
            }
            Divider()
            Toggle("Hidden in selector", isOn: Binding(
                get: { role.tag?.hidden ?? false },
                set: { model.setTag(ModelTag(name: role.tag?.name ?? role.name, color: role.tag?.color, hidden: $0), for: role.name) }
            ))
        } label: {
            Label("Tag", systemImage: "tag")
        }
        .menuStyle(.borderlessButton)
        .frame(width: 70)
    }

    private var modelTitle: String {
        switch role.selector {
        case .model(let qualifiedId, _):
            model.model(for: role.selector)?.name ?? qualifiedId
        case .role(let target):
            "Same as @\(target)"
        case .empty:
            "Not set"
        }
    }

    private var tint: Color {
        switch role.color {
        case "accent": .accentColor
        case "success": .green
        case "warning": .orange
        case "error": .red
        case "info": .blue
        default: .secondary
        }
    }
}
