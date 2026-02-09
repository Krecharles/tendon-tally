import Foundation
import Cocoa
import os.log

/// Monitors keyboard and mouse events system-wide using NSEvent monitors.
///
/// Uses both global (other apps) and local (this app) monitors to track
/// key presses, mouse clicks, scroll events, and mouse movement distance.
/// All tracking is passive (listen-only) and does not record key contents, only counts.
/// Follows OctoMouse's approach: https://github.com/KonsomeJona/OctoMouse
final class EventTapManager {
    private var globalMonitors: [Any] = []
    private var localMonitors: [Any] = []

    private let queue = DispatchQueue(label: "TendonTally.EventTapManager")
    private var lastMouseLocation: CGPoint?

    /// Current snapshot is updated on `queue` and read via `snapshot()` API.
    private var _snapshot = RawActivitySnapshot()

    /// Called on the main thread when permissions appear to be missing.
    var onPermissionOrTapFailure: ((String) -> Void)?

    /// Called on the main thread when event monitoring is successfully started.
    var onPermissionGranted: (() -> Void)?

    private let logger = Logger(subsystem: "com.tendontally", category: "EventTapManager")
    private var retryTimer: Timer?
    private var hasRegisteredMonitors = false

    /// Start monitoring events. If no events are received (permissions missing), retries periodically.
    func start() {
        DispatchQueue.main.async { [weak self] in
            self?.registerMonitors()
        }
    }

    private func registerMonitors() {
        guard !hasRegisteredMonitors else { return }

        // Check if we can create an event tap as a permission probe.
        // NSEvent global monitors silently fail without permissions,
        // so we use a CGEvent tap check to detect missing permissions.
        let hasPermission = checkAccessibilityPermission()

        if !hasPermission {
            onPermissionOrTapFailure?("Unable to monitor input events. Check Accessibility / Input Monitoring permissions.")
            startRetryTimer()
            return
        }

        stopRetryTimer()
        hasRegisteredMonitors = true
        logger.info("Registering NSEvent monitors...")

        // Key down — filter out auto-repeat so holding a key counts as one stroke
        let keyHandler: (NSEvent) -> NSEvent? = { [weak self] event in
            if !event.isARepeat {
                self?.queue.async { self?._snapshot.keyPressCount += 1 }
            }
            return event
        }
        addMonitors(matching: .keyDown, handler: keyHandler)

        // Mouse clicks
        let leftClickHandler: (NSEvent) -> NSEvent? = { [weak self] event in
            self?.queue.async { self?._snapshot.mouseClickCount += 1 }
            return event
        }
        addMonitors(matching: .leftMouseDown, handler: leftClickHandler)

        let rightClickHandler: (NSEvent) -> NSEvent? = { [weak self] event in
            self?.queue.async { self?._snapshot.mouseClickCount += 1 }
            return event
        }
        addMonitors(matching: .rightMouseDown, handler: rightClickHandler)

        let otherClickHandler: (NSEvent) -> NSEvent? = { [weak self] event in
            self?.queue.async { self?._snapshot.mouseClickCount += 1 }
            return event
        }
        addMonitors(matching: .otherMouseDown, handler: otherClickHandler)

        // Scroll wheel
        let scrollHandler: (NSEvent) -> NSEvent? = { [weak self] event in
            let deltaY = abs(event.scrollingDeltaY)
            let magnitude: Int
            if event.hasPreciseScrollingDeltas {
                // Trackpad: convert pixel deltas to approximate ticks
                magnitude = max(1, Int(deltaY / 10))
            } else {
                magnitude = Int(deltaY)
            }
            if magnitude > 0 {
                self?.queue.async { self?._snapshot.scrollTicks += magnitude }
            }
            return event
        }
        addMonitors(matching: .scrollWheel, handler: scrollHandler)

        // Mouse movement
        let moveHandler: (NSEvent) -> NSEvent? = { [weak self] event in
            let location = NSEvent.mouseLocation
            self?.queue.async {
                guard let self else { return }
                if let last = self.lastMouseLocation {
                    let dx = Double(location.x - last.x)
                    let dy = Double(location.y - last.y)
                    let distance = (dx * dx + dy * dy).squareRoot()
                    self._snapshot.mouseDistance += distance
                }
                self.lastMouseLocation = location
            }
            return event
        }
        addMonitors(matching: .mouseMoved, handler: moveHandler)

        // Mouse dragging (also counts as movement)
        let dragHandler: (NSEvent) -> NSEvent? = { [weak self] event in
            let location = NSEvent.mouseLocation
            self?.queue.async {
                guard let self else { return }
                if let last = self.lastMouseLocation {
                    let dx = Double(location.x - last.x)
                    let dy = Double(location.y - last.y)
                    let distance = (dx * dx + dy * dy).squareRoot()
                    self._snapshot.mouseDistance += distance
                }
                self.lastMouseLocation = location
            }
            return event
        }
        addMonitors(matching: .leftMouseDragged, handler: dragHandler)
        addMonitors(matching: .rightMouseDragged, handler: dragHandler)

        onPermissionGranted?()
    }

    private func addMonitors(matching mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> NSEvent?) {
        // Global monitor: events in other apps. Handler returns Void (can't modify events).
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { event in
            _ = handler(event)
        }) {
            globalMonitors.append(global)
            logger.info("Global monitor registered for mask: \(mask.rawValue)")
        } else {
            logger.error("Failed to register global monitor for mask: \(mask.rawValue)")
        }

        // Local monitor: events in this app. Handler can return modified event.
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: handler) {
            localMonitors.append(local)
            logger.info("Local monitor registered for mask: \(mask.rawValue)")
        } else {
            logger.error("Failed to register local monitor for mask: \(mask.rawValue)")
        }
    }

    private func checkAccessibilityPermission() -> Bool {
        let trusted = AXIsProcessTrusted()
        logger.info("AXIsProcessTrusted: \(trusted)")
        return trusted
    }

    private func startRetryTimer() {
        guard retryTimer == nil else { return }
        retryTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.registerMonitors()
        }
    }

    private func stopRetryTimer() {
        retryTimer?.invalidate()
        retryTimer = nil
    }

    /// Stop and remove all event monitors.
    func stop() {
        DispatchQueue.main.async { [weak self] in
            self?.stopRetryTimer()
        }
        for monitor in globalMonitors {
            NSEvent.removeMonitor(monitor)
        }
        globalMonitors.removeAll()
        for monitor in localMonitors {
            NSEvent.removeMonitor(monitor)
        }
        localMonitors.removeAll()
        hasRegisteredMonitors = false
        queue.async { [weak self] in
            self?.lastMouseLocation = nil
            self?._snapshot = RawActivitySnapshot()
        }
    }

    /// Thread-safe snapshot of the current raw activity counts.
    func snapshot() -> RawActivitySnapshot {
        var result = RawActivitySnapshot()
        queue.sync {
            result = _snapshot
        }
        return result
    }

    /// Reset the raw counters (used when rolling to a new window).
    /// Synchronous so that the next snapshot() call reads zeroes.
    func resetCounters() {
        queue.sync {
            self._snapshot = RawActivitySnapshot()
        }
    }
}
