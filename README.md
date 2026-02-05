## TendonTally – macOS Activity Tracker (Menu Bar App)

This project is a Swift + SwiftUI based macOS menu bar application that helps you monitor your computer usage:

- **Key presses** (count only, no key contents)
- **Mouse clicks**
- **Scroll events and approximate scroll distance**
- **Mouse movement distance**

Activity is tracked in **rolling 5‑minute windows**, and a simple **dashboard** in a popover shows the current window and recent history. The architecture is inspired by the open‑source project [OctoMouse](https://github.com/KonsomeJona/OctoMouse), but implemented in Swift with SwiftUI and an AppKit bridge.

### Project layout

- `App/` – SwiftUI `@main` app entry point, `NSStatusItem`/popover wiring, and shared app state.
- `Domain/` – Core business logic: `EventTapManager` (event monitoring), `MetricsAggregator` (rolling windows), `PersistenceController` (data storage), `SettingsManager` (user preferences), and `TimeSeriesCalculator` (chart data).
- `Models/` – Shared data types: `UsageSample`, `RawActivitySnapshot`, `MetricTypes` (TimeFrame, MetricType, AggregatedMetrics, TimeSeriesDataPoint).
- `UI/` – SwiftUI views: `DashboardView` (popover), `FullDashboardView` (main window), `SettingsView`, `BarChartView`, and `MetricsViewModel`.

### Running with Swift Package Manager (SweetPad/Command Line)

This project is configured to work with Swift Package Manager, so you can build and run it from the command line without opening Xcode:

**Quick start:**
```bash
# Build the project
swift build

# Run the app
swift run TendonTally

# Or use the convenience script
./run.sh
```

**Requirements:**
- macOS 14.0 or later
- Swift 5.9 or later
- Xcode Command Line Tools installed

The app will appear as a **menu bar icon** and open the dashboard popover on click.

### Running with Xcode

If you prefer to use Xcode:

1. Open `TendonTally/TendonTally.xcodeproj` in Xcode.
2. Ensure the **deployment target** is macOS 14.0 or later.
3. Build & run. The app will appear as a **menu bar icon** and open the dashboard popover on click.

### Privacy

This app is designed with privacy in mind:

- It **does not record which keys** you press, only **how many** keys are pressed.
- It does not transmit any data over the network.
- All metrics are simple counts and distances used for self‑monitoring.

To enable global keyboard and mouse monitoring, you must grant the app **Accessibility** and/or **Input Monitoring** permissions in:

> System Settings → Privacy & Security → Accessibility / Input Monitoring

The app will show an in‑app explanation and instructions if permissions are missing.

