import ProjectDescription

let projectName = "Pergamenum"
// Bundle identifier is lowercase by specification (SPEC §2), unlike the folder name.
let bundleId = "it.stefer.pergamenum"
// macOS 26 Tahoe baseline: no compatibility fallbacks for earlier releases (SPEC §2, §14).
let deploymentTarget = "26.0"

let baseSettings: SettingsDictionary = [
    "DEVELOPMENT_TEAM": "T7H24G7BFW",
    "CODE_SIGN_STYLE": "Automatic",
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
            dependencies: []
        ),
        .target(
            name: "\(projectName)Tests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "\(bundleId).tests",
            deploymentTargets: .macOS(deploymentTarget),
            infoPlist: .default,
            sources: ["Tests/**"],
            dependencies: [.target(name: projectName)]
        ),
    ]
)
