//
//  OhMyPiApp.swift
//  OhMyPi
//
//  Created by Arman Sarvardin on 22/9/26.
//

import OSLog
import SwiftUI

let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "sh.omp.desktop",
    category: "app"
)

@main
struct OhMyPiApp: App {
    @NSApplicationDelegateAdaptor private var delegate: Delegate
    @State private var workspaceStateModel = WorkspaceStateModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(workspaceStateModel)
                .environment(\.appCommands, delegate.commands)
                .frame(minWidth: 900, minHeight: 560)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Project…") {
                    delegate.commands.send(.openProject)
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("New Session") {
                    delegate.commands.send(.newSession)
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            CommandMenu("Models") {
                Button("Models & Providers…") {
                    delegate.commands.send(.showModelRoles)
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            }
        }

        Window("Models", id: WindowID.modelRoles) {
            ModelsWindow()
                .environment(workspaceStateModel)
                .environment(\.appCommands, delegate.commands)
        }
        .defaultSize(width: 860, height: 600)

        Settings {
            Preferences()
        }
    }
}

enum WindowID {
    static let modelRoles = "model-roles"
}
