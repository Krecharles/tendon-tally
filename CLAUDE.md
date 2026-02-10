# TendonTally - macOS Activity Tracker

## Overview
Menu bar app tracking keyboard/mouse activity in 5-minute rolling windows. SwiftUI + AppKit, macOS 14+, Swift 5.9+.

## Architecture
- **App/** - Entry point (@main), NSStatusItem, AppState singleton
- **Domain/** - EventTapManager (event tap), MetricsAggregator (5-min windows), PersistenceController (JSON storage), TimeSeriesCalculator
- **Domain/Protocols/** - EventTapping, MetricsPersisting, MetricsAggregating (for testability/DI)
- **Models/** - UsageSample, MetricTypes, RawActivitySnapshot
- **UI/** - MetricsViewModel (MVVM), FullDashboardView (shell with sidebar), DashboardView (popover)
- **UI/Components/** - Reusable views: MetricTile, PermissionBanner, SidebarButton, MetricPill, KUIWeightRow
- **UI/Tabs/** - TodayTabView, HistoryTabView, KUITabView (split from FullDashboardView)
- **UI/Extensions/** - MetricType+Color

## Build & Run
```bash
swift build        # Build with SPM
swift run TendonTally  # Run from CLI
swift test         # Run tests
./run.sh          # Convenience script
```

## Build System
- **Primary:** Swift Package Manager (Package.swift)
- **Xcode project:** Used ONLY for Assets.xcassets management
  - Do NOT add source files to Xcode project
  - Assets changes require Xcode, then rebuild with SPM

## Key Patterns
- Data flow: EventTapManager -> MetricsAggregator (callbacks) -> MetricsViewModel (@Published) -> Views
- Protocols (EventTapping, MetricsPersisting, MetricsAggregating) enable dependency injection
- MetricsAggregator accepts dependencies via init for testability
- AppPreferences centralizes all UserDefaults access

## Note on Prompts
The user often dictates prompts via speech-to-text. If something seems off, try to interpret what was intended — the dictation software may have misheard or misinterpreted words.

## Critical Files
- `UI/FullDashboardView.swift` - Main dashboard shell with sidebar navigation
- `Domain/MetricsAggregator.swift` - Core windowing logic with DI support
- `UI/MetricsViewModel.swift` - View model bridging domain to UI
- `Domain/TimeSeriesCalculator.swift` - Complex time bucketing for charts
