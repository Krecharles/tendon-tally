// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TendonTally",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "TendonTally",
            targets: ["TendonTally"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "TendonTally",
            dependencies: [],
            path: ".",
            exclude: [
                "TendonTally/TendonTally.xcodeproj",
                "TendonTally/TendonTally/TendonTally.icon",
                "README.md",
                "AGENTS.md",
                "CLAUDE.md",
                "assets",
                "run.sh",
                "Tests"
            ],
            sources: [
                // App entry point and status bar
                "App/MainApp.swift",
                "App/StatusItemController.swift",
                "App/AppState.swift",
                // Domain logic
                "Domain/EventTapManager.swift",
                "Domain/MetricsAggregator.swift",
                "Domain/PersistenceController.swift",
                "Domain/SettingsManager.swift",
                "Domain/TimeSeriesCalculator.swift",
                "Domain/BreaksEvaluator.swift",
                "Domain/BreakPillController.swift",
                // Domain protocols
                "Domain/Protocols/EventTapping.swift",
                "Domain/Protocols/MetricsPersisting.swift",
                "Domain/Protocols/MetricsAggregating.swift",
                // Domain state
                "Domain/AppPreferences.swift",
                // Models
                "Models/UsageSample.swift",
                "Models/RawActivitySnapshot.swift",
                "Models/MetricTypes.swift",
                "Models/Breaks.swift",
                // UI components
                "UI/MetricsViewModel.swift",
                "UI/DashboardView.swift",
                "UI/FullDashboardView.swift",
                "UI/SettingsView.swift",
                "UI/BarChartView.swift",
                "UI/BreakPillPanel.swift",
                // UI - Extracted components
                "UI/Components/MetricTile.swift",
                "UI/Components/PermissionBanner.swift",
                "UI/Components/SidebarButton.swift",
                "UI/Components/MetricPill.swift",
                "UI/Components/KUIWeightRow.swift",
                // UI - Tab views
                "UI/Tabs/TodayTabView.swift",
                "UI/Tabs/HistoryTabView.swift",
                "UI/Tabs/KUITabView.swift",
                "UI/Tabs/BreaksTabView.swift",
                "UI/Tabs/PermissionsTabView.swift",
                // UI - Extensions
                "UI/Extensions/MetricType+Color.swift"
            ],
            resources: [
                .process("TendonTally/TendonTally/Assets.xcassets")
            ],
            linkerSettings: [
                .linkedFramework("SwiftUI", .when(platforms: [.macOS])),
                .linkedFramework("AppKit", .when(platforms: [.macOS])),
                .linkedFramework("CoreGraphics", .when(platforms: [.macOS])),
                .linkedFramework("ServiceManagement", .when(platforms: [.macOS]))
            ]
        ),
        // Test target imports and exercises the real application module
        .testTarget(
            name: "TendonTallyTests",
            dependencies: ["TendonTally"],
            path: "Tests",
            linkerSettings: [
                .linkedFramework("CoreGraphics", .when(platforms: [.macOS]))
            ]
        )
    ]
)
