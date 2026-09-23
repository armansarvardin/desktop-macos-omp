//
//  SessionsSidebar.swift
//  OhMyPi
//
//  Created by Arman Sarvardin on 22/9/26.
//

import SwiftUI

/// Projects with their live and stored sessions.
struct SessionsSidebar: View {
    @Environment(WorkspaceStateModel.self) private var workspaceStateModel
    @Environment(\.openSettings) private var openSettings

    @Binding var selection: String?

    private struct ProjectRows: Identifiable {
        var project: WorkspaceStateModel.Project
        var live: [AgentSessionStateModel]
        var stored: [StoredSession]

        var id: String { project.id }
    }

    /// Built in `body` so Observation tracks live session changes; List row
    /// builders are evaluated lazily and would miss them otherwise.
    private var rows: [ProjectRows] {
        workspaceStateModel.projects.map { project in
            ProjectRows(
                project: project,
                live: workspaceStateModel.liveSessions(for: project),
                stored: workspaceStateModel.storedSessions(for: project)
            )
        }
    }

    var body: some View {
        let rows = rows

        List(selection: $selection) {
            ForEach(rows) { entry in
                let project = entry.project

                Section {
                    ForEach(entry.live) { session in
                        SessionRow(
                            title: session.displayTitle,
                            subtitle: liveSubtitle(for: session),
                            isLive: true,
                            isStreaming: session.isStreaming
                        )
                        .tag(session.id)
                        .contextMenu {
                            Button("Close Session") {
                                workspaceStateModel.close(session)
                            }
                        }
                    }

                    ForEach(entry.stored) { stored in
                        SessionRow(
                            title: stored.displayTitle,
                            subtitle: stored.modifiedAt.formatted(.relative(presentation: .named)),
                            isLive: false,
                            isStreaming: false
                        )
                        .tag(stored.id)
                    }
                } header: {
                    sectionHeader(for: project)
                }
            }
        }
        .listStyle(.sidebar)
        .onChange(of: selection) { _, newValue in
            // Selecting a stored row resumes it; the live row then takes over the selection.
            guard
                let newValue,
                let stored = workspaceStateModel.projects
                    .flatMap(\.sessions)
                    .first(where: { $0.id == newValue })
            else {
                return
            }
            workspaceStateModel.open(stored)
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button {
                    workspaceStateModel.addProject()
                } label: {
                    Label("Open Project", systemImage: "folder.badge.plus")
                }

                Spacer()

                Button {
                    openSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Preferences")
            }
            .buttonStyle(.borderless)
            .padding(10)
            .background(.bar)
        }
        .overlay {
            if workspaceStateModel.projects.isEmpty {
                ContentUnavailableView(
                    "No projects yet",
                    systemImage: "folder",
                    description: Text("Open a folder to get started.")
                )
            }
        }
    }

    // MARK: - Subviews

    private func sectionHeader(for project: WorkspaceStateModel.Project) -> some View {
        HStack {
            Text(verbatim: project.name)
                .lineLimit(1)
                .help(project.url.path)

            Spacer()

            Button {
                workspaceStateModel.newSession(in: project.url)
            } label: {
                Image(systemName: "plus.bubble")
            }
            .buttonStyle(.borderless)
            .help("New session in \(project.name)")
        }
        .contextMenu {
            Button("New Session") {
                workspaceStateModel.newSession(in: project.url)
            }
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([project.url])
            }
            Divider()
            Button("Remove from Sidebar", role: .destructive) {
                workspaceStateModel.removeProject(project)
            }
        }
    }

    private func liveSubtitle(for session: AgentSessionStateModel) -> String {
        switch session.status {
        case .launching: "Starting…"
        case .ready: session.isStreaming ? "Working…" : (session.currentModel?.name ?? "Ready")
        case .exited(let code): code == 0 ? "Exited" : "Exited (\(code))"
        case .failed(let message): message
        }
    }
}

#Preview {
    @Previewable @State var selection: String?

    SessionsSidebar(selection: $selection)
        .withPreviewEnvironment()
        .frame(width: 260, height: 500)
}
