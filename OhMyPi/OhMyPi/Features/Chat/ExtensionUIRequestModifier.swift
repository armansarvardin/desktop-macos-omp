//
//  ExtensionUIRequestModifier.swift
//  OhMyPi
//
//  Created by Arman Sarvardin on 22/9/26.
//

import SwiftUI

/// Presents tool approvals, `ask` pickers and text prompts as sheets.
struct ExtensionUIRequestModifier: ViewModifier {
    let session: AgentSessionStateModel

    func body(content: Content) -> some View {
        content
            .sheet(item: activeRequest) { request in
                ExtensionUIRequestSheet(request: request) { response in
                    session.respond(to: request, with: response)
                }
            }
    }

    private var activeRequest: Binding<ExtensionUIRequest?> {
        Binding(
            get: { session.activeUIRequest },
            set: { newValue in
                // Dismissing the sheet (Escape) cancels the request.
                if newValue == nil, let request = session.activeUIRequest {
                    session.respond(to: request, with: .cancelled)
                }
            }
        )
    }
}

extension View {
    func extensionUIRequests(for session: AgentSessionStateModel) -> some View {
        modifier(ExtensionUIRequestModifier(session: session))
    }
}

// MARK: - Sheet

struct ExtensionUIRequestSheet: View {
    let request: ExtensionUIRequest
    let respond: (ExtensionUIResponse) -> Void

    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch request.method {
            case .select(let title, let options, let details):
                titleView(title)
                selectOptions(options, details: details)

            case .confirm(let title, let message):
                titleView(title)
                Text(verbatim: message)
                    .textSelection(.enabled)
                confirmButtons

            case .input(let title, let placeholder):
                titleView(title)
                TextField(placeholder ?? "", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { respond(.value(text)) }
                submitButtons

            case .editor(let title, let prefill):
                titleView(title)
                TextEditor(text: $text)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 160)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color(nsColor: .separatorColor))
                    }
                    .onAppear { text = prefill ?? "" }
                submitButtons

            default:
                titleView("Unsupported request")
                cancelButton
            }
        }
        .padding(20)
        .frame(minWidth: 420, idealWidth: 520, maxWidth: 720)
    }

    // MARK: - Subviews

    /// Approval prompts pack the command into the title after the first line.
    @ViewBuilder
    private func titleView(_ title: String) -> some View {
        let lines = title.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let headline = lines.first ?? title
        let body = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

        VStack(alignment: .leading, spacing: 8) {
            Label(headline, systemImage: headline.lowercased().hasPrefix("allow") ? "lock.shield" : "questionmark.bubble")
                .font(.headline)

            if !body.isEmpty {
                CodeBlock(language: nil, code: body, maxHeight: 220)
            }
        }
    }

    private func selectOptions(_ options: [String], details: [String?]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                Button {
                    respond(.value(option))
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: option)
                            .fontWeight(option == "Approve" ? .semibold : .regular)
                        if details.indices.contains(index), let detail = details[index] {
                            Text(verbatim: detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.bordered)
                .tint(option == "Deny" ? .red : option == "Approve" ? .accentColor : nil)
                .keyboardShortcut(index == 0 ? .defaultAction : index == 1 && option == "Deny" ? .cancelAction : nil)
            }

            HStack {
                Spacer()
                cancelButton
            }
        }
    }

    private var confirmButtons: some View {
        HStack {
            Spacer()
            Button("No") { respond(.confirmed(false)) }
                .keyboardShortcut(.cancelAction)
            Button("Yes") { respond(.confirmed(true)) }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        }
    }

    private var submitButtons: some View {
        HStack {
            Spacer()
            cancelButton
            Button("Submit") { respond(.value(text)) }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        }
    }

    private var cancelButton: some View {
        Button("Cancel") { respond(.cancelled) }
            .keyboardShortcut(.cancelAction)
    }
}

#Preview("Approval") {
    ExtensionUIRequestSheet(
        request: ExtensionUIRequest(
            frame: [
                "id": "ui_1", "method": "select",
                "title": "Allow tool: bash\nReason: Critical pattern detected\n$ rm -rf build",
                "options": ["Approve", "Deny"]
            ]
        )!,
        respond: { _ in }
    )
}

#Preview("Input") {
    ExtensionUIRequestSheet(
        request: ExtensionUIRequest(frame: ["id": "ui_2", "method": "input", "title": "Paste the callback URL"])!,
        respond: { _ in }
    )
}
