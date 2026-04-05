# TendonTally (macOS)

TendonTally is a native macOS menu bar app that turns computer activity into a clear workload signal, so you can spot heavy days before they pile up.

## What it does

- Tracks key presses, mouse clicks, scroll activity, and mouse movement distance
- Uses rolling 1-minute windows for live activity feedback
- Shows a quick menu bar dashboard and a full dashboard view
- Includes Today and History views for trend tracking over time
- Includes optional break reminders with configurable work/break timing and snooze options
- Data stays local on your Mac

## Download

- Latest DMG: `https://github.com/Krecharles/tendon-tally/releases/latest/download/TendonTally.dmg`
- All releases: `https://github.com/Krecharles/tendon-tally/releases/latest`

## Run from source

Requirements: macOS 14+, Swift 5.9+, Xcode Command Line Tools.

```bash
swift build
swift run TendonTally
# or
./run.sh
```

When first launched, macOS will ask for Accessibility/Input Monitoring permissions so activity can be measured.
