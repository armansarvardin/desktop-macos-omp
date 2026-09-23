# Oh My Pi for macOS

Native SwiftUI desktop client for the [`omp`](https://omp.sh) coding agent. It spawns
`omp --mode rpc-ui` per session and talks to it over the JSONL RPC protocol, so
everything the CLI can do (models, roles, thinking levels, tool approvals, slash
commands, session resume) is available from a window.

Bundle identifier: `sh.omp.desktop`. License: MIT, same as the rest of the repository.

## Requirements

- macOS 15 or later to run
- Xcode 26 or later to build (Swift 6.2 toolchain: default actor isolation, `nonisolated` types)
- `omp` 18.x installed; the app finds it on your login shell `PATH`, or at the path set in
  Preferences

## Build & run

```bash
scripts/build.sh --run
```

This is a plain `xcodebuild` wrapper. The Debug build is signed ad hoc, so it runs on
your own machine without an Apple Developer account. Output lands in
`build/Build/Products/Debug/OhMyPi.app`. Opening `OhMyPi.xcodeproj` in Xcode and
pressing Run works the same way; the shared `OhMyPi` scheme is checked in.

Build settings live in `Config/*.xcconfig`, not in the project file:

| File | Purpose |
|---|---|
| `Config/Base.xcconfig` | bundle id, version, deployment target, Swift settings, Info.plist keys |
| `Config/Debug.xcconfig`, `Config/Release.xcconfig` | per-configuration optimisation and debug info |
| `Config/Local.xcconfig` | your signing team, git-ignored; copy `Local.xcconfig.example` to create it |

The app runs without the App Sandbox on purpose: it has to spawn `omp` and let it edit
arbitrary project folders, which the sandbox forbids. Hardened runtime is enabled for
signed builds (Xcode drops it for ad-hoc signatures).

## Signing and releases

Contributors do not need to sign anything. To ship a build to other people:

1. Copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and set your
   `DEVELOPMENT_TEAM` and `CODE_SIGN_IDENTITY = Developer ID Application`.
2. Store notarization credentials once:
   `xcrun notarytool store-credentials omp --apple-id … --team-id … --password …`
3. Run `NOTARY_PROFILE=omp scripts/release.sh`.

The script archives the Release configuration, exports with Developer ID
(`scripts/ExportOptions.plist`), wraps the app in `build/OhMyPi-<version>.dmg`,
notarizes and staples it. Without `NOTARY_PROFILE` it produces an ad-hoc signed DMG,
which is what CI attaches to tagged releases.

Bump `MARKETING_VERSION` in `Config/Base.xcconfig` for a new release and push a
`macos-app-v<version>` tag; the `macOS app` GitHub Actions workflow
(`.github/workflows/macos-app.yml`) builds the DMG and attaches it to the GitHub release.

## App icon

`OhMyPi/Assets.xcassets/AppIcon.appiconset` is generated, not hand-drawn:

```bash
swift scripts/generate-app-icon.swift OhMyPi/Assets.xcassets/AppIcon.appiconset
```

## Features

- **Projects sidebar**: recent folders plus every project that has sessions under
  `~/.omp/agent/sessions`. Stored sessions are listed with title and age; clicking one
  resumes it with `--resume`.
- **Streaming transcript**: markdown (headings, lists, quotes, fenced code with copy),
  collapsible thinking, tool-call cards with arguments and output, notices, compaction.
- **Composer**: Return sends, Shift+Return inserts a newline. While the agent works,
  Return steers the running turn, Queue sends a follow-up, Stop aborts (⌘.).
- **Slash commands**: typing `/` opens a palette with every command the runtime
  advertises (builtins, skills, extensions, custom and file commands) filtered as you
  type, including subcommand completion (`/fast ` → on/off/status). ↑↓ choose, Tab
  completes, Return runs, Esc clears. Builtin output shows in the transcript.
- **Model & thinking**: model and thinking-level pills in the status bar. The model
  picker lists configured roles first (smol, slow, plan, custom tags…); choosing one
  applies the role's model and effort suffix to the current session. Full catalog
  below, plus Cycle Model (⌃⌘M) and fast mode in the pill menu.
- **Models & Roles window** (⇧⌘M, also in Preferences and the chat menu): assign a
  model and effort suffix to each role, add custom roles with a tag name and colour,
  and drag the cycle order. Reads and writes `modelRoles`, `modelTags` and
  `cycleOrder` through `omp config get/set --json`, preserving the file's key order.
- **Providers tab** of the same window: every provider the CLI knows, with its sign-in
  state; enable or disable providers (`disabledProviders`), run OAuth logins through the
  runtime, store API keys in `~/.omp/agent/.env`, refresh the catalog, and pick which of a
  provider's models are offered (`enabledModels`).
- **Tool approvals**: `extension_ui_request` frames (approve/deny, `ask` pickers, text
  prompts, editors) are shown as sheets. Set the approval mode in Preferences.
- **Status bar**: context usage, tokens per second, queued messages, extension status
  lines.

## Layout

```
OhMyPi/
├── Config/                      # xcconfig build settings
├── scripts/                     # build.sh, release.sh, ExportOptions.plist, icon generator
├── OhMyPi.xcodeproj/            # project + shared scheme (user data is ignored)
└── OhMyPi/
    ├── OhMyPiApp.swift          # @main, menu commands, scenes
    ├── OhMyPiApp+Delegate.swift # app delegate, owns the command channel
    ├── ContentView.swift        # root view, consumes app commands
    ├── PreviewEnvironment.swift # mock transport/config + .withPreviewEnvironment()
    ├── Features/
    │   ├── Workspace/           # split view shell and empty state
    │   ├── Sessions/            # sidebar and rows
    │   ├── Chat/                # transcript, rows, composer, status bar, UI request sheets
    │   ├── Models/              # model picker, catalog picker
    │   ├── ModelRoles/          # Models window shell and roles tab
    │   ├── Providers/           # providers tab, model and API key sheets
    │   └── Preferences/         # settings window
    └── Shared/
        ├── StateModels/         # @Observable Workspace, AgentSession, ModelRoles models
        ├── Logic/Rpc/           # transport (Process + pipes), client, commands, wire models
        ├── Logic/Config/        # omp config client, role/selector models
        ├── Logic/Launch/        # launch settings, one-shot command runner
        ├── Logic/Transcript/    # transcript items and the event reducer
        ├── Logic/Sessions/      # on-disk session store and path encoding
        ├── Logic/Commands/      # slash command matching
        ├── Logic/Markdown/      # block-level markdown parser
        ├── Logic/AppCommands.swift  # AsyncChannel of menu/delegate commands
        ├── Views/               # MarkdownText, CodeBlock, StatusPill
        ├── Environments/        # @Entry keys
        └── Helpers/             # AppStorage keys, approval mode, ANSI stripping
```

Conventions: bare-noun screen types, `XxxStateModel` observables injected through the
environment, one modifier per line, `MARK: -` sections, and `#Preview` blocks seeded
with `.withPreviewEnvironment()`. Menu and delegate events travel over an
`AsyncChannel` from swift-async-algorithms (the only dependency).

## Protocol notes

- Protocol v2 is negotiated on start so large frames arrive as `rpc_chunk` sequences;
  `RpcFrameDecoder` reassembles them.
- Streaming text is accumulated from `message_update` deltas; `message_end` is authoritative.
- A turn is finished on `agent_end` unless `isTerminal` is `false`.
- The RPC protocol has no session listing, so `SessionStore` scans the CLI's session
  directory and mirrors its cwd encoding in `SessionPaths`.
- `/model <selector>` does not resolve over RPC, so role switching resolves the role in
  the app and sends `set_model` plus `set_thinking_level`.

## Contributing

Keep the code style above, run `scripts/build.sh` before opening a pull request, and
avoid committing anything under `Config/Local.xcconfig` or `build/`.
