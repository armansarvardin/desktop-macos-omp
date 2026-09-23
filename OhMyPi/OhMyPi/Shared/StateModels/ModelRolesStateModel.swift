//
//  ModelRolesStateModel.swift
//  OhMyPi
//
//  Created by Arman Sarvardin on 22/9/26.
//

import Foundation
import Observation
import SwiftUI

/// Editable copy of `modelRoles`, `modelTags` and `cycleOrder` from the CLI config.
@Observable
final class ModelRolesStateModel {
    enum Phase: Equatable {
        case idle
        case loading
        case saving
        case failed(String)
    }

    // MARK: - Stored properties

    private(set) var roles: [ModelRole] = []
    /// Role names in cycle order; the source of truth for `cycleOrder`.
    private(set) var cycleOrder: [String] = []
    private(set) var availableModels: [RpcModel] = []
    private(set) var phase: Phase = .idle
    private(set) var isLoadingModels = false
    private(set) var lastSavedAt: Date?

    private let configClient: OmpConfigClient
    private let launcher: RpcLauncher
    private let launchSettings: () -> LaunchSettings
    private var savedSnapshot: [ModelRole] = []
    private var savedCycleOrder: [String] = []
    private var savedRawTags: [String: JSONValue] = [:]
    private var savedRoleKeyOrder: [String] = []
    private var savedTagKeyOrder: [String] = []

    // MARK: - Initialization

    init(
        configClient: OmpConfigClient,
        launcher: RpcLauncher,
        launchSettings: @escaping () -> LaunchSettings = { LaunchSettings.current() }
    ) {
        self.configClient = configClient
        self.launcher = launcher
        self.launchSettings = launchSettings
    }

    // MARK: - Computed properties

    var hasChanges: Bool {
        roles != savedSnapshot || cycleOrder != savedCycleOrder
    }

    var cycleRoles: [ModelRole] {
        cycleOrder.compactMap { name in roles.first { $0.name == name } }
    }

    var builtInRoles: [ModelRole] {
        roles.filter(\.isBuiltIn)
    }

    var customRoles: [ModelRole] {
        roles.filter { !$0.isBuiltIn }
    }

    func model(for selector: ModelSelector) -> RpcModel? {
        guard let qualifiedId = selector.qualifiedId else { return nil }
        return availableModels.first { $0.qualifiedId == qualifiedId }
    }

    // MARK: - Loading

    func load() async {
        phase = .loading

        do {
            async let rolesValue = configClient.get("modelRoles")
            async let tagsValue = configClient.get("modelTags")
            async let cycleValue = configClient.get("cycleOrder")
            let (rolesConfig, tagsConfig, cycleConfig) = try await (rolesValue, tagsValue, cycleValue)

            let assignments = rolesConfig.value.objectValue ?? [:]
            let tags = tagsConfig.value.objectValue ?? [:]
            let cycle = cycleConfig.value.arrayValue?.compactMap(\.stringValue) ?? []

            savedRawTags = tags
            savedRoleKeyOrder = rolesConfig.keyOrder
            savedTagKeyOrder = tagsConfig.keyOrder

            var names = ModelRole.builtInOrder
            for name in assignments.keys.sorted() + tags.keys.sorted() + cycle where !names.contains(name) {
                names.append(name)
            }

            roles = names.map { name in
                ModelRole(
                    name: name,
                    selector: ModelSelector(rawValue: assignments[name]?.stringValue ?? ""),
                    tag: tags[name].flatMap(ModelTag.init(json:)),
                    isInCycle: cycle.contains(name)
                )
            }
            cycleOrder = cycle.filter { name in roles.contains { $0.name == name } }

            savedSnapshot = roles
            savedCycleOrder = cycleOrder
            phase = .idle
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Uses a live session's catalog when one is open; otherwise boots a headless agent.
    func loadModels(preferring models: [RpcModel]) async {
        if !models.isEmpty {
            availableModels = models
            return
        }

        guard availableModels.isEmpty, !isLoadingModels else { return }
        isLoadingModels = true
        defer { isLoadingModels = false }

        do {
            let transport = try launcher.launch(launchSettings().headlessRpcConfiguration())
            let client = RpcClient(transport: transport)
            defer { client.shutdown() }

            try await client.waitUntilReady()
            try await client.request(.negotiateProtocol(version: 2))
            let payload = try await client.request(.getAvailableModels)
            let models = try payload?["models"]?.decoded(as: [RpcModel].self) ?? []
            availableModels = models.sorted { ($0.provider, $0.name.lowercased()) < ($1.provider, $1.name.lowercased()) }
        } catch {
            phase = .failed("Could not load models: \(error.localizedDescription)")
        }
    }

    // MARK: - Editing

    func assign(_ selector: ModelSelector, to roleName: String) {
        update(roleName) { $0.selector = selector }
    }

    func setEffort(_ effort: String?, for roleName: String) {
        update(roleName) { $0.selector = $0.selector.withEffort(effort) }
    }

    func setInCycle(_ isInCycle: Bool, for roleName: String) {
        update(roleName) { $0.isInCycle = isInCycle }
        cycleOrder.removeAll { $0 == roleName }
        if isInCycle {
            cycleOrder.append(roleName)
        }
    }

    func setTag(_ tag: ModelTag?, for roleName: String) {
        update(roleName) { $0.tag = tag }
    }

    func moveInCycle(from source: IndexSet, to destination: Int) {
        cycleOrder.move(fromOffsets: source, toOffset: destination)
    }

    func addRole(named rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: " ", with: "-")
        guard !name.isEmpty, !roles.contains(where: { $0.name == name }) else { return }
        roles.append(ModelRole(name: name, selector: .empty, tag: ModelTag(name: rawName.trimmingCharacters(in: .whitespaces)), isInCycle: false))
    }

    func removeRole(named roleName: String) {
        guard let role = roles.first(where: { $0.name == roleName }), !role.isBuiltIn else { return }
        roles.removeAll { $0.name == roleName }
        cycleOrder.removeAll { $0 == roleName }
    }

    func discardChanges() {
        roles = savedSnapshot
        cycleOrder = savedCycleOrder
    }

    // MARK: - Saving

    func save() async {
        phase = .saving

        // Keep the file's existing key order; new keys go last in registry order.
        func ordered(by fileOrder: [String]) -> [ModelRole] {
            roles.enumerated().sorted { lhs, rhs in
                let left = fileOrder.firstIndex(of: lhs.element.name).map { ($0, 0) } ?? (Int.max, lhs.offset)
                let right = fileOrder.firstIndex(of: rhs.element.name).map { ($0, 0) } ?? (Int.max, rhs.offset)
                return left < right
            }.map(\.element)
        }

        let assignments = ordered(by: savedRoleKeyOrder).compactMap { role -> (String, JSONValue)? in
            role.selector == .empty ? nil : (role.name, .string(role.selector.rawValue))
        }

        var tagEntries: [(String, String)] = ordered(by: savedTagKeyOrder).compactMap { role in
            role.tag.map { (role.name, $0.json) }
        }
        for name in savedTagKeyOrder where !roles.contains(where: { $0.name == name }) {
            if let raw = savedRawTags[name] {
                tagEntries.append((name, OmpConfigClient.encode(raw)))
            }
        }
        let tagsJSON = "{" + tagEntries.map { "\(OmpConfigClient.encode(.string($0))):\($1)" }.joined(separator: ",") + "}"

        do {
            try await configClient.set("modelRoles", OmpConfigClient.orderedObject(assignments))
            try await configClient.set("modelTags", tagsJSON)
            try await configClient.set("cycleOrder", OmpConfigClient.array(cycleOrder.map(JSONValue.string)))
            savedSnapshot = roles
            savedCycleOrder = cycleOrder
            lastSavedAt = .now
            phase = .idle
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: - Private

    private func update(_ roleName: String, _ mutate: (inout ModelRole) -> Void) {
        guard let index = roles.firstIndex(where: { $0.name == roleName }) else { return }
        mutate(&roles[index])
    }
}
