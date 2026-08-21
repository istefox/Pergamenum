import ProjectDescription

let projectName = "Pergamenum"
// Bundle identifier is lowercase by specification (SPEC §2), unlike the folder name.
let bundleId = "it.stefer.pergamenum"
// macOS 26 Tahoe baseline: no compatibility fallbacks for earlier releases (SPEC §2, §14).
let deploymentTarget = "26.0"

let baseSettings: SettingsDictionary = [
    "DEVELOPMENT_TEAM": "T7H24G7BFW",
    "CODE_SIGN_STYLE": "Automatic",
    // Without this the default is "-", an ad-hoc signature, and the team above is
    // never used. That is not cosmetic: TCC keys a privacy grant to the signing
    // identity, and an ad-hoc signature has none, so it keys on the binary hash
    // instead. Every rebuild then throws away the Calendar and Reminders permission -
    // grant access, change one line, and the app is a stranger to macOS again. It
    // cost an afternoon to recognise, twice mistaken for a broken read.
    "CODE_SIGN_IDENTITY": "Apple Development",
    "SWIFT_VERSION": "6.0",
    // Named explicitly rather than left to the default: without it the asset catalog
    // compiles the set and nothing points the bundle at it, so the app ships with the
    // generic document icon and the set looks like it did not work.
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
]

// Release only, and on the app target only. Notarization rejects a bundle without the
// hardened runtime, and exportArchive signs with whatever the project declares - so
// leaving this out meant every Developer ID export came back unhardened and had to be
// re-signed by hand before it could be submitted, which is how the first two builds were
// notarized.
//
// It cannot go in the shared base: the unit test bundle is hosted inside the app, at
// Contents/PlugIns, and the hardened runtime refuses to dlopen code signed by a different
// team - which is exactly what a test bundle is. Enabling it everywhere builds an app that
// ships correctly and cannot run its own tests. Debug therefore stays unhardened, and
// nothing is ever distributed from Debug.
let appConfigurations: [Configuration] = [
    .debug(name: "Debug"),
    .release(name: "Release", settings: ["ENABLE_HARDENED_RUNTIME": "YES"]),
]

// The version shown in Informazioni. Raised by hand when the app reaches a version
// worth naming; the build number underneath it is what tells two builds apart.
let marketingVersion = "1.0"

// The number of commits behind HEAD, handed in by `scripts/release.sh` as
// TUIST_BUILD_NUMBER. Not a counter kept in this file: a counter has to be remembered,
// and every notarized build until now went out as 1.0 (1), so nothing on disk said
// which one it was.
//
// Zero means nobody handed one in, which is what an ordinary `tuist generate` does.
// A build numbered 0 is therefore a development build by construction, and the release
// script refuses to ship one.
let buildNumber = Environment.buildNumber.getString(default: "0")

// The files `perg` compiles alongside its own, named rather than globbed from
// `Sources/**` (ADR-0007 §D2).
//
// The same files on disk as the app's, in a second binary: no framework, no module
// boundary, nothing turned `public`, and therefore no second implementation of the
// harness conventions to drift from the first. What is left out is what needs a user
// interface or a permission dialog - VaultController and every view, ThumbnailStore
// (AppKit, PDFKit, QuickLook), VaultWatcher, and the EventKit half of Sources/Calendar.
//
// The exclusion of MailLink.swift is the one surprise: it is the single file under
// Sources/Core that imports AppKit, and only the menu bar calls it. Leaving it in would
// link AppKit into a command-line tool for a function the tool cannot use.
//
// This list is deliberately explicit. A new file under Sources/Core is picked up by the
// glob and, if it imports SwiftUI, breaks this build loudly - which is the rule of
// ADR-0001 §D1 enforcing itself instead of being remembered.
let sharedSources: [SourceFileGlob] = [
    .glob("Sources/Core/**", excluding: ["Sources/Core/Email/MailLink.swift"]),
    // The vault as an answer: the payload shapes and the operations behind both
    // connectors, so `perg --json` and an MCP tool call cannot drift apart.
    .glob("Sources/Connector/**"),
    "Sources/Index/IndexCache.swift",
    "Sources/Index/IndexSnapshot.swift",
    "Sources/Calendar/TimeBlock.swift",
    "Sources/Vault/CanvasStore.swift",
    "Sources/Vault/NoteFileOperations.swift",
    "Sources/Vault/NoteHistory.swift",
    "Sources/Vault/NoteStore.swift",
    "Sources/Vault/NoteTree.swift",
    "Sources/Vault/PinnedTagsStore.swift",
    "Sources/Vault/RecentVaults.swift",
    "Sources/Vault/StarredStore.swift",
    "Sources/Vault/VaultScanner.swift",
    "Sources/Vault/VaultSession.swift",
    "Sources/Vault/VaultSession+Diary.swift",
    "Sources/Vault/VaultSession+Files.swift",
    "Sources/Vault/VaultSession+Journal.swift",
    "Sources/Vault/VaultSession+Notes.swift",
    "Sources/Vault/VaultSession+Search.swift",
    "Sources/Vault/VaultSession+Starred.swift",
    "Sources/Vault/VaultSession+TagRename.swift",
    "Sources/Vault/VaultSession+Tasks.swift",
    "Sources/Vault/VaultSession+TimeBlocks.swift",
    "Sources/Vault/VaultSession+Watching.swift",
    "Sources/Vault/VaultSettings.swift",
    "Sources/Vault/WriteJournal.swift",
]

let project = Project(
    name: projectName,
    settings: .settings(base: baseSettings),
    targets: [
        .target(
            name: projectName,
            destinations: .macOS,
            product: .app,
            bundleId: bundleId,
            deploymentTargets: .macOS(deploymentTarget),
            infoPlist: .extendingDefault(with: [
                // Both spelled out: the default Tuist extends carries 1.0 and 1, so
                // without these every build ever made claimed to be the same one.
                "CFBundleShortVersionString": .string(marketingVersion),
                "CFBundleVersion": .string(buildNumber),
                // Without this the about panel prints "Copyright ©. All rights
                // reserved." with nothing between the symbol and the full stop, which
                // is the panel the build number is read from.
                "NSHumanReadableCopyright": "© 2026 Stefano Ferri",
                "CFBundleURLTypes": [
                    [
                        "CFBundleURLName": .string(bundleId),
                        "CFBundleURLSchemes": ["pergamenum"],
                    ],
                ],
                "NSCalendarsFullAccessUsageDescription": "Pergamenum mostra e crea eventi nella timeline giornaliera.",
                "NSRemindersFullAccessUsageDescription": "Pergamenum sincronizza i task con Promemoria.",
            ]),
            // Everything but the CLI: `Sources/CLI/main.swift` is top-level code, and a
            // module that contains any cannot also carry an `@main` type - the app
            // stopped compiling the moment the glob swallowed it.
            sources: .init(globs: [
                .glob("Sources/**", excluding: ["Sources/CLI/**", "Sources/MCPServer/**"]),
            ]),
            resources: ["Resources/**"],
            dependencies: [],
            // Repeated on the target because a target-level value wins over the
            // project base, and the generated target carries "-" by default.
            settings: .settings(base: baseSettings, configurations: appConfigurations)
        ),
        .target(
            name: "\(projectName)Tests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "\(bundleId).tests",
            deploymentTargets: .macOS(deploymentTarget),
            infoPlist: .default,
            sources: ["Tests/**"],
            // The theme and vocabulary files are bundled into the test target as
            // well: a @testable import resolves Bundle(for:) to the test bundle, so
            // without this the completeness tests would silently have nothing to check.
            resources: ["Resources/Themes/**", "Resources/vocabolari.json"],
            dependencies: [.target(name: projectName)]
        ),
        // The board's pointer behaviour cannot be reached from the unit suite: what
        // broke in SPEC §6.3 and §6.5 was hit testing and gesture priority, and both
        // exist only once SwiftUI has laid the views out and a real drag arrives.
        // This target drives the running app and reads the result back off disk.
        .target(
            name: "\(projectName)UITests",
            destinations: .macOS,
            product: .uiTests,
            bundleId: "\(bundleId).uitests",
            deploymentTargets: .macOS(deploymentTarget),
            infoPlist: .default,
            sources: ["UITests/**"],
            dependencies: [.target(name: projectName)],
            settings: .settings(base: baseSettings)
        ),
        // The command-line half of ADR-0007: the vault reachable without the app.
        //
        // Not sandboxed and not hardened - it is run from a shell on this machine, and
        // the hardened runtime is for what gets notarized and distributed. EventKit is
        // deliberately absent (ADR-0007 §D4): TCC attributes a command-line tool's
        // calendar access to the terminal that launched it, not to Pergamenum.
        .target(
            name: "perg",
            destinations: .macOS,
            product: .commandLineTool,
            bundleId: "\(bundleId).cli",
            deploymentTargets: .macOS(deploymentTarget),
            infoPlist: .default,
            sources: SourceFilesList(globs: sharedSources + ["Sources/CLI/**"]),
            dependencies: [],
            settings: .settings(base: baseSettings)
        ),
        // The other half of ADR-0007: the same vault, spoken to over MCP.
        //
        // The one target in this project with an external dependency. It compiles the
        // same shared files as `perg` and calls `VaultSession` in the same process - it
        // does not shell out to the CLI, which would put a text format between two
        // programs that can pass values.
        .target(
            name: "pergamenum-mcp",
            destinations: .macOS,
            product: .commandLineTool,
            bundleId: "\(bundleId).mcp",
            deploymentTargets: .macOS(deploymentTarget),
            infoPlist: .default,
            sources: SourceFilesList(globs: sharedSources + ["Sources/MCPServer/**"]),
            dependencies: [.external(name: "MCP")],
            // A hyphen is not a Swift identifier, so the generated PRODUCT_NAME comes
            // out as `pergamenum_mcp` and the binary with it. The module keeps the
            // underscored name, which nothing reads; the file on disk is what goes in a
            // client's configuration, and it should be the name the docs use.
            settings: .settings(base: baseSettings.merging([
                "PRODUCT_NAME": "pergamenum-mcp",
                "PRODUCT_MODULE_NAME": "pergamenum_mcp",
            ]))
        ),
    ]
)
