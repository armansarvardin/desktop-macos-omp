//
//  Preferences.swift
//  OhMyPi
//
//  Created by Arman Sarvardin on 22/9/26.
//

import SwiftUI

/// Settings window: how the `omp` process is launched.
struct Preferences: View {
    @AppStorage(.AppStorageKey.executablePath)
    private var executablePath = "omp"

    @AppStorage(.AppStorageKey.useLoginShell)
    private var useLoginShell = true

    @AppStorage(.AppStorageKey.approvalMode)
    private var approvalMode = ApprovalMode.default.rawValue

    @AppStorage(.AppStorageKey.extraArguments)
    private var extraArguments = ""

    @AppStorage(.AppStorageKey.showThinking)
    private var showThinking = true

    @Environment(\.openWindow) private var openWindow

    private static let candidatePaths = [
        "~/.bun/bin/omp",
        "/opt/homebrew/bin/omp",
        "/usr/local/bin/omp",
        "~/.local/bin/omp"
    ]

    var body: some View {
        Form {
            Section("Executable") {
                HStack {
                    TextField("Command or path", text: $executablePath)
                        .textFieldStyle(.roundedBorder)

                    Button("Detect") {
                        detectExecutable()
                    }
                }

                Toggle("Launch through login shell (zsh -lic)", isOn: $useLoginShell)

                Text("The login shell makes your shell functions, aliases and PATH available, which is required when `omp` is wrapped by a function in your .zshrc. Turn it off to run the path above directly.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Models") {
                HStack {
                    Text("Enable providers, store API keys, pick their models, and assign models to roles.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Models & Providers…") {
                        openWindow(id: WindowID.modelRoles)
                    }
                }
            }

            Section("Tool approval") {
                Picker("Approval mode", selection: $approvalMode) {
                    ForEach(ApprovalMode.allCases) { mode in
                        Text(mode.title)
                            .tag(mode.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)

                Text("Applies to new sessions. Approval prompts appear as sheets in the chat.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Advanced") {
                TextField("Extra CLI arguments", text: $extraArguments, prompt: Text("--thinking high --model smol"))
                    .textFieldStyle(.roundedBorder)

                Toggle("Show thinking blocks in transcript", isOn: $showThinking)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .padding(.vertical, 8)
    }

    private func detectExecutable() {
        let found = Self.candidatePaths
            .map { ($0 as NSString).expandingTildeInPath }
            .first { FileManager.default.isExecutableFile(atPath: $0) }

        if let found {
            executablePath = found
        }
    }
}

#Preview {
    Preferences()
}
