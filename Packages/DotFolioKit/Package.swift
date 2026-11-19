// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DotFolioKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "DotFolioModels", targets: ["DotFolioModels"]),
        .library(name: "DotFolioSecurity", targets: ["DotFolioSecurity"]),
        .library(name: "DotFolioCore", targets: ["DotFolioCore"]),
        .library(name: "DotFolioEnv", targets: ["DotFolioEnv"]),
        .library(name: "DotFolioIntegrations", targets: ["DotFolioIntegrations"]),
    ],
    targets: [
        .target(name: "DotFolioModels"),
        .target(name: "DotFolioSecurity"),
        // Use cases combining metadata (Models) and secrets (Security).
        .target(name: "DotFolioCore", dependencies: ["DotFolioModels", "DotFolioSecurity", "DotFolioEnv"]),
        // Pure .env parsing/exporting (no dependencies, shared with the future CLI).
        .target(name: "DotFolioEnv"),
        // GitHub/GitLab REST clients. Read-only by design.
        .target(name: "DotFolioIntegrations"),
        .testTarget(name: "DotFolioModelsTests", dependencies: ["DotFolioModels"]),
        .testTarget(name: "DotFolioSecurityTests", dependencies: ["DotFolioSecurity"]),
        .testTarget(name: "DotFolioCoreTests", dependencies: ["DotFolioCore"]),
        .testTarget(name: "DotFolioEnvTests", dependencies: ["DotFolioEnv"]),
        .testTarget(name: "DotFolioIntegrationsTests", dependencies: ["DotFolioIntegrations"]),
    ]
)
