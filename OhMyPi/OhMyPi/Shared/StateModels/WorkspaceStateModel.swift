//
//  WorkspaceStateModel.swift
//  OhMyPi
//
//  Created by Arman Sarvardin on 22/9/26.
//

import AppKit
import Foundation
import Observation
import OSLog

/// App-wide state: known projects, their stored sessions and the live ones.
@Observable
final class WorkspaceStateModel {
    struct Project: Identifiable, Hashable {
        var url: URL
        var sessions: [StoredSession]

        var id: String { url.path }
        var name: String { url.lastPathComponent }
    }

    // MARK: - Stored properties

    private(set) var projects: [Project] = []
    private(set) var openSessions: [AgentSessionStateModel] = []
    /// Roles from `modelRoles` / `modelTags`, in `cycleOrder` first.
    private(set) var roles: [ModelRole] = []
    var selectedSessionId: String?

    private let sessionStore: SessionStore
    private let launcher: RpcLauncher
    private let configClient: OmpConfigClient
    private let defaults: UserDefaults

    // MARK: - Initialization

    init(
        sessionStore: SessionStore = SessionStore(),
        launcher: RpcLauncher = .default,
        configClient: OmpConfigClient = .default,
        defaults: UserDefaults = .standard
    ) {
        self.sessionStore = sessionStore
        self.launcher = launcher
        self.configClient = configClient
        self.defaults = defaults
    }

    // MARK: - Computed properties

    var selectedSession: AgentSessionStateModel? {
        openSessions.first { $0.id == selectedSessionId }
    }

    func liveSessions(for project: Project) -> [AgentSessionStateModel] {
        openSessions.filter { $0.projectURL.path == project.url.path }
    }

    /// Stored sessions that are not already open in a live process.
    func storedSessions(for project: Project) -> [StoredSession] {
        let openFiles = Set(openSessions.compactMap { $0.sessionFileURL?.path })
        return project.sessions.filter { !openFiles.contains($0.fileURL.path) }
    }

    // MARK: - Roles

    /// Roles that resolve to a model and are not hidden, for quick switching.
    var switchableRoles: [ModelRole] {
        roles.filter { role in
            role.tag?.hidden != true && ModelRoleResolver.resolve(role.name, in: roles) != nil
        }
    }

    func reloadRoles() async {
        do {
            async let rolesValue = configClient.get("modelRoles")
            async let tagsValue = configClient.get("modelTags")
            async let cycleValue = configClient.get("cycleOrder")
            let (rolesConfig, tagsConfig, cycleConfig) = try await (rolesValue, tagsValue, cycleValue)

            let assignments = rolesConfig.value.objectValue ?? [:]
            let tags = tagsConfig.value.objectValue ?? [:]
            let cycle = cycleConfig.value.arrayValue?.compactMap(\.stringValue) ?? []

            var names = cycle
            for name in ModelRole.builtInOrder + assignments.keys.sorted() where !names.contains(name) {
                names.append(name)
            }

            roles = names.compactMap { name in
                guard assignments[name] != nil || ModelRole.builtIn[name] != nil else { return nil }
                return ModelRole(
                    name: name,
                    selector: ModelSelector(rawValue: assignments[name]?.stringValue ?? ""),
                    tag: tags[name].flatMap(ModelTag.init(json:)),
                    isInCycle: cycle.contains(name)
                )
            }
        } catch {
            logger.error("Could not load model roles: \(error.localizedDescription)")
        }
    }

    // MARK: - Projects

    func refresh() {
        let recent = (defaults.stringArray(forKey: .AppStorageKey.recentProjects) ?? [])
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
        let known = sessionStore.knownProjects()

        var seen = Set<String>()
        let urls = (recent + known).filter { url in
            seen.insert(url.path).inserted && FileManager.default.fileExists(atPath: url.path)
        }

        projects = urls.map { Project(url: $0, sessions: sessionStore.sessions(for: $0)) }
    }

    func refreshSessions(for projectURL: URL) {
        guard let index = projects.firstIndex(where: { $0.url.path == projectURL.path }) else { return }
        projects[index].sessions = sessionStore.sessions(for: projectURL)
    }

    func addProject() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Project"
        panel.message = "Choose a folder for oh-my-pi to work in"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        openProject(at: url)
    }

    func openProject(at url: URL) {
        var recent = defaults.stringArray(forKey: .AppStorageKey.recentProjects) ?? []
        recent.removeAll { $0 == url.path }
        recent.insert(url.path, at: 0)
        defaults.set(Array(recent.prefix(30)), forKey: .AppStorageKey.recentProjects)

        refresh()
        newSession(in: url)
    }

    func removeProject(_ project: Project) {
        var recent = defaults.stringArray(forKey: .AppStorageKey.recentProjects) ?? []
        recent.removeAll { $0 == project.url.path }
        defaults.set(recent, forKey: .AppStorageKey.recentProjects)

        liveSessions(for: project).forEach(close)
        projects.removeAll { $0.id == project.id }
    }

    // MARK: - Sessions

    @discardableResult
    func newSession(in projectURL: URL) -> AgentSessionStateModel {
        let session = AgentSessionStateModel(
            projectURL: projectURL,
            launcher: launcher,
            launchConfiguration: launchConfiguration(for: projectURL, resume: nil)
        )
        register(session)
        return session
    }

    func open(_ stored: StoredSession) {
        if let existing = openSessions.first(where: { $0.sessionFileURL?.path == stored.fileURL.path }) {
            selectedSessionId = existing.id
            return
        }

        let session = AgentSessionStateModel(
            projectURL: stored.projectURL,
            resume: stored.fileURL,
            title: stored.displayTitle,
            launcher: launcher,
            launchConfiguration: launchConfiguration(for: stored.projectURL, resume: stored.fileURL)
        )
        register(session)
    }

    func close(_ session: AgentSessionStateModel) {
        session.stop()
        openSessions.removeAll { $0.id == session.id }

        if selectedSessionId == session.id {
            selectedSessionId = openSessions.last?.id
        }

        refreshSessions(for: session.projectURL)
    }

    func closeAll() {
        openSessions.forEach { $0.stop() }
    }

    // MARK: - Private

    private func register(_ session: AgentSessionStateModel) {
        openSessions.append(session)
        selectedSessionId = session.id

        Task {
            await session.start()
            refreshSessions(for: session.projectURL)
        }
    }

    private func launchConfiguration(for projectURL: URL, resume fileURL: URL?) -> RpcLaunchConfiguration {
        LaunchSettings.current(defaults: defaults).rpcConfiguration(for: projectURL, resume: fileURL)
    }
}
