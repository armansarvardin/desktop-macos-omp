//
//  ModelsWindow.swift
//  OhMyPi
//
//  Created by Arman Sarvardin on 23/9/26.
//

import SwiftUI

/// The "Models" window: role assignments on one tab, providers on the other.
struct ModelsWindow: View {
    enum Tab: String, CaseIterable, Identifiable {
        case roles
        case providers

        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .roles: "Roles"
            case .providers: "Providers"
            }
        }
    }

    @State private var tab: Tab = .roles

    var body: some View {
        Group {
            switch tab {
            case .roles:
                ModelRoles()
            case .providers:
                Providers()
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Section", selection: $tab) {
                    ForEach(Tab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
    }
}

#Preview {
    ModelsWindow()
        .withPreviewEnvironment()
        .frame(width: 860, height: 600)
}
