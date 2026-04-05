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

- CI release is tag-driven via `.github/workflows/release.yml`
- Push stable tag `vX.Y.Z` to publish a GitHub Release with:
  - `TendonTally.dmg` (stable permalink target)
  - `TendonTally-vX.Y.Z.dmg` (versioned artifact)
  - `SHA256SUMS.txt`
- Workflow gates:
  - tag must match `vX.Y.Z`
  - tag version must equal Xcode `MARKETING_VERSION`
  - archive build must succeed
  - DMG sign/notarize/staple/validate must succeed
- Workflow runs on GitHub-hosted `macos-15` (public repo standard runner)
- Required repo secrets for release workflow:
  - `SIGN_IDENTITY` (Developer ID Application identity string)
  - `NOTARY_PROFILE` (notarytool keychain profile name, e.g. `TENDON_TALLY_NOTARY`)
  - `BUILD_CERTIFICATE_BASE64` (base64-encoded `.p12` Developer ID cert export)
  - `P12_PASSWORD` (password used for `.p12` export)
  - `APPLE_ID` (Apple ID email for notarization)
  - `APPLE_APP_SPECIFIC_PASSWORD` (Apple app-specific password for notarization)
  - `APPLE_TEAM_ID` (Apple Developer team ID)

Local manual packaging (fallback):
- Build unsigned DMG with `./make-dmg.sh v1` (replace `v1` with release label)
- Build + sign + notarize + staple + validate:
  `SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE="TENDON_TALLY_NOTARY" ./make-dmg.sh v1 --all`
- Output DMG path: `release-output/TendonTally-v1.dmg`
- Script applies drag-to-Applications DMG layout with no background by default
- Script blesses the mounted volume so Finder opens the install window on mount
- Optional custom background: `BACKGROUND_IMAGE=/path/to/background.png ./make-dmg.sh v1`
- Optional icon layout tweak: `ICON_LEFT_X=220 ICON_RIGHT_X=580 ICON_Y=230 ./make-dmg.sh v1`
- `NOTARY_PROFILE` must already exist in keychain (`xcrun notarytool store-credentials ...`)

## Build System

- **Primary:** Swift Package Manager (Package.swift)
- **Xcode project:** Used for release archive/export signing pipeline and Assets.xcassets management
  - Keep source of truth in SPM targets for app code
  - Assets and release signing/archive flow depend on `TendonTally/TendonTally.xcodeproj`

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
