## macOS Activity Tracker (Menu Bar App)

This project is a Swift + SwiftUI based macOS menu bar application that helps you monitor your computer usage:

- **Key presses** (count only, no key contents)
- **Mouse clicks**
- **Scroll events and approximate scroll distance**
- **Mouse movement distance**

Activity is tracked in **rolling 5‑minute windows**, and a simple **dashboard** in a popover shows the current window and recent history. The architecture is inspired by the open‑source project [OctoMouse](https://github.com/KonsomeJona/OctoMouse), but implemented in Swift with SwiftUI and an AppKit bridge.

### Project layout

- `App/` – SwiftUI `@main` app and `NSStatusItem`/popover wiring.
- `Domain/` – `EventTapManager`, `MetricsAggregator`, and `UsageSample` model.
- `UI/` – SwiftUI `DashboardView` and `MetricsViewModel`.

To use this in Xcode:

1. Create a new **macOS App** project in Xcode using **SwiftUI App** lifecycle.
2. Add the `App`, `Domain`, and `UI` folders from this repository into the project (as groups with “Create folder references” or “Create groups”, as you prefer).
3. Ensure the **deployment target** is macOS 13 or later for SF Symbols and SwiftUI features.
4. Build & run. The app will appear as a **menu bar icon** and open the dashboard popover on click.

### Privacy

This app is designed with privacy in mind:

- It **does not record which keys** you press, only **how many** keys are pressed.
- It does not transmit any data over the network.
- All metrics are simple counts and distances used for self‑monitoring.

To enable global keyboard and mouse monitoring, you must grant the app **Accessibility** and/or **Input Monitoring** permissions in:

> System Settings → Privacy & Security → Accessibility / Input Monitoring

The app will show an in‑app explanation and instructions if permissions are missing.

