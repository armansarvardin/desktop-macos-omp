//
//  ContentView.swift
//  OhMyPi
//
//  Created by Arman Sarvardin on 22/9/26.
//

import AsyncAlgorithms
import SwiftUI

struct ContentView: View {
    @Environment(WorkspaceStateModel.self) private var workspaceStateModel
    @Environment(\.appCommands) private var appCommands
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Workspace()
            .task {
                workspaceStateModel.refresh()
                await workspaceStateModel.reloadRoles()
            }
            .task {
                for await command in appCommands.commands {
                    handle(command)
                }
            }
    }

    // MARK: - Commands

    private func handle(_ command: AppCommands.Command) {
        switch command {
        case .openProject:
            workspaceStateModel.addProject()

        case .newSession:
            guard let projectURL = workspaceStateModel.selectedSession?.projectURL
                ?? workspaceStateModel.projects.first?.url
            else {
                workspaceStateModel.addProject()
                return
            }
            workspaceStateModel.newSession(in: projectURL)

        case .showModelRoles:
            openWindow(id: WindowID.modelRoles)

        case .terminate(let reply):
            workspaceStateModel.closeAll()
            reply()
        }
    }
}

#Preview {
    ContentView()
        .withPreviewEnvironment()
}
