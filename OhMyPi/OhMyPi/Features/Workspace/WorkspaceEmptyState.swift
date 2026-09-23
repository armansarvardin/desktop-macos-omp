//
//  WorkspaceEmptyState.swift
//  OhMyPi
//
//  Created by Arman Sarvardin on 22/9/26.
//

import SwiftUI

/// Shown when no session is selected.
struct WorkspaceEmptyState: View {
    @Environment(WorkspaceStateModel.self) private var workspaceStateModel

    var body: some View {
        ContentUnavailableView {
            Label("No session selected", systemImage: "terminal")
        } description: {
            Text("Open a project folder to start a new oh-my-pi session, or pick a stored session from the sidebar.")
        } actions: {
            Button("Open Project…") {
                workspaceStateModel.addProject()
            }
            .keyboardShortcut("o", modifiers: .command)

            if let project = workspaceStateModel.projects.first {
                Button("New session in \(project.name)") {
                    workspaceStateModel.newSession(in: project.url)
                }
            }
        }
    }
}

#Preview {
    WorkspaceEmptyState()
        .withPreviewEnvironment()
}
