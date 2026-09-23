//
//  Workspace.swift
//  OhMyPi
//
//  Created by Arman Sarvardin on 22/9/26.
//

import SwiftUI

/// Main window: project/session sidebar on the left, active chat on the right.
struct Workspace: View {
    @Environment(WorkspaceStateModel.self) private var workspaceStateModel

    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        @Bindable var workspaceStateModel = workspaceStateModel

        NavigationSplitView(columnVisibility: $columnVisibility) {
            SessionsSidebar(selection: $workspaceStateModel.selectedSessionId)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 380)
        } detail: {
            if let session = workspaceStateModel.selectedSession {
                Chat(session: session)
                    .id(session.id)
            } else {
                WorkspaceEmptyState()
            }
        }
        .navigationTitle(workspaceStateModel.selectedSession?.displayTitle ?? "Oh My Pi")
        .navigationSubtitle(workspaceStateModel.selectedSession?.projectURL.path ?? "")
    }
}

#Preview {
    Workspace()
        .withPreviewEnvironment()
        .frame(width: 1_000, height: 640)
}
