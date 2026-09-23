//
//  OhMyPiApp+Delegate.swift
//  OhMyPi
//
//  Created by Arman Sarvardin on 22/9/26.
//

import AppKit

extension OhMyPiApp {
    final class Delegate: NSObject, NSApplicationDelegate {
        /// Shared with every scene through the environment.
        let commands = AppCommands()

        private var didReplyToTermination = false

        func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
            true
        }

        /// Defers quitting until the main window has shut its agent processes down.
        /// A short fallback still quits when no window is left to consume the command.
        func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
            didReplyToTermination = false
            let delegate = self

            commands.send(.terminate {
                Task { @MainActor in
                    delegate.finishTermination()
                }
            })

            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.5))
                delegate.finishTermination()
            }

            return .terminateLater
        }

        private func finishTermination() {
            guard !didReplyToTermination else { return }
            didReplyToTermination = true
            NSApplication.shared.reply(toApplicationShouldTerminate: true)
        }
    }
}
