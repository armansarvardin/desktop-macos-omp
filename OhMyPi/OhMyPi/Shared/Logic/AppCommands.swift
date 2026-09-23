//
//  AppCommands.swift
//  OhMyPi
//
//  Created by Arman Sarvardin on 23/9/26.
//

import AsyncAlgorithms
import Foundation

/// App-level commands raised by menus and the application delegate and
/// consumed by the main window. Replaces NotificationCenter with a channel:
/// `send` suspends until a consumer takes the command, so nothing is dropped
/// while the window is still appearing.
nonisolated struct AppCommands: Sendable {
    enum Command: Sendable {
        case openProject
        case newSession
        case showModelRoles
        /// Quit was requested; call `reply` once sessions are shut down.
        case terminate(reply: @Sendable () -> Void)
    }

    let commands = AsyncChannel<Command>()

    /// Fire-and-forget from synchronous call sites such as menu actions.
    func send(_ command: Command) {
        Task {
            await commands.send(command)
        }
    }
}
