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
                "TendonTally/TendonTally/Assets.xcassets",
                "TendonTally/TendonTally.xcodeproj",
                "README.md"
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
                // Models
                "Models/UsageSample.swift",
                "Models/RawActivitySnapshot.swift",
                "Models/MetricTypes.swift",
                // UI components
                "UI/MetricsViewModel.swift",
                "UI/DashboardView.swift",
                "UI/FullDashboardView.swift",
                "UI/SettingsView.swift",
                "UI/BarChartView.swift"
            ],
            linkerSettings: [
                .linkedFramework("SwiftUI", .when(platforms: [.macOS])),
                .linkedFramework("AppKit", .when(platforms: [.macOS])),
                .linkedFramework("CoreGraphics", .when(platforms: [.macOS])),
                .linkedFramework("ServiceManagement", .when(platforms: [.macOS]))
            ]
        )
    ]
)
