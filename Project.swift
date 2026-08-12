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
                "CFBundleURLTypes": [
                    [
                        "CFBundleURLName": .string(bundleId),
                        "CFBundleURLSchemes": ["pergamenum"],
                    ],
                ],
                "NSCalendarsFullAccessUsageDescription": "Pergamenum mostra e crea eventi nella timeline giornaliera.",
                "NSRemindersFullAccessUsageDescription": "Pergamenum sincronizza i task con Promemoria.",
            ]),
            sources: ["Sources/**"],
            resources: ["Resources/**"],
            dependencies: [],
            // Repeated on the target because a target-level value wins over the
            // project base, and the generated target carries "-" by default.
            settings: .settings(base: baseSettings)
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
    ]
)
