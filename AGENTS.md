# TendonTally - macOS Activity Tracker

## Overview

Menu bar app tracking keyboard/mouse activity in 1-minute rolling windows. SwiftUI + AppKit, macOS 14+, Swift 5.9+.

## Architecture

- **App/** - Entry point (@main), NSStatusItem lifecycle, AppState singleton
- **Domain/** - EventTapManager (event tap), MetricsAggregator (1-min windows), PersistenceController (JSON storage), TimeSeriesCalculator, break reminder evaluation/controllers, settings/state services
- **Domain/Protocols/** - EventTapping, MetricsPersisting, MetricsAggregating (for testability/DI)
- **Models/** - UsageSample, MetricTypes, RawActivitySnapshot, Breaks/KUI config models
- **UI/** - MetricsViewModel (MVVM), FullDashboardView (shell with sidebar), DashboardView (popover), SettingsView
- **UI/Components/** - Reusable views: MetricTile, PermissionBanner, SidebarButton, MetricPill, KUIWeightRow
- **UI/Tabs/** - TodayTabView, HistoryTabView, KUITabView, BreaksTabView, PermissionsTabView
- **UI/Extensions/** - MetricType+Color

## Build & Run

```bash
swift build        # Build with SPM
swift run TendonTally  # Run from CLI
swift test         # Run tests
./run.sh          # Convenience script
```

## Release Packaging

- Drop exported app bundle at `release-input/TendonTally.app`
- Build unsigned DMG with `./make-dmg.sh v1` (replace `v1` with release version label)
- Build + sign + notarize + staple + validate in one run:
  `SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE="TENDON_TALLY_NOTARY" ./make-dmg.sh v1 --all`
- Output DMG is written to `release-output/TendonTally-v1.dmg`
- Script applies drag-to-Applications DMG layout with no background by default
- Script blesses the mounted volume so Finder opens the install window on mount
- Optional custom background: `BACKGROUND_IMAGE=/path/to/background.png ./make-dmg.sh v1`
- Optional icon layout tweak: `ICON_LEFT_X=220 ICON_RIGHT_X=580 ICON_Y=230 ./make-dmg.sh v1`
- `NOTARY_PROFILE` must already exist in keychain (`xcrun notarytool store-credentials ...`)

## Build System

- **Primary:** Swift Package Manager (Package.swift)
- **Xcode project:** Used ONLY for Assets.xcassets management
  - Do NOT add source files to Xcode project
  - Assets changes require Xcode, then rebuild with SPM

## Key Patterns

- Data flow: EventTapManager -> MetricsAggregator (callbacks) -> MetricsViewModel (@Published) -> Views
- Protocols (EventTapping, MetricsPersisting, MetricsAggregating) enable dependency injection
- MetricsAggregator accepts dependencies via init for testability
- AppPreferences centralizes dashboard/break state in UserDefaults; launch-at-login and dock visibility are applied through SettingsManager

## Note on Prompts

The user often dictates prompts via speech-to-text. If something seems off, try to interpret what was intended — the dictation software may have misheard or misinterpreted words.

## Critical Files

- `UI/FullDashboardView.swift` - Main dashboard shell with sidebar navigation
- `Domain/MetricsAggregator.swift` - Core windowing logic with DI support
- `UI/MetricsViewModel.swift` - View model bridging domain to UI
- `Domain/TimeSeriesCalculator.swift` - Complex time bucketing for charts
