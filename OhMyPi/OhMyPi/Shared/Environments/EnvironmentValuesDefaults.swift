//
//  EnvironmentValuesDefaults.swift
//  OhMyPi
//
//  Created by Arman Sarvardin on 22/9/26.
//

import SwiftUI

extension EnvironmentValues {
    // MARK: - Services

    @Entry var sessionStore = SessionStore()
    @Entry var rpcLauncher: RpcLauncher = .default
    @Entry var ompConfigClient: OmpConfigClient = .default
    @Entry var modelCatalogService: ModelCatalogService = .default

    // MARK: - Commands

    @Entry var appCommands = AppCommands()
}
