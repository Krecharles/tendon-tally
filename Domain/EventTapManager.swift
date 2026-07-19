import Foundation
import Cocoa
import ApplicationServices
import os.log

/// Monitors keyboard and mouse events system-wide using NSEvent monitors.
///
/// Uses both global (other apps) and local (this app) monitors to track
/// key presses, mouse clicks, scroll events, and mouse movement distance.
/// All tracking is passive (listen-only) and does not record key contents, only counts.
/// Follows OctoMouse's approach: https://github.com/KonsomeJona/OctoMouse
final class EventTapManager {
    struct PermissionStatus: Equatable {
        let accessibilityGranted: Bool
        let inputMonitoringGranted: Bool

        var allRequiredGranted: Bool {
            accessibilityGranted && inputMonitoringGranted
        }

        var guidanceMessage: String {
            switch (accessibilityGranted, inputMonitoringGranted) {
            case (false, false):
                return "Accessibility and Input Monitoring permissions are required to monitor keyboard and mouse activity."
            case (false, true):
                return "Accessibility permission is required to monitor keyboard and mouse activity."
            case (true, false):
                return "Input Monitoring permission is required to count keyboard activity."
            case (true, true):
                return ""
            }
        }
    }

    private var globalMonitors: [Any] = []
    private var localMonitors: [Any] = []

    private let stateLock = NSLock()
    private var lastMouseLocation: CGPoint?
    private var activityNotificationScheduled = false
    private var activityNotificationGeneration = 0

    /// Current snapshot is protected by `stateLock` and read via `snapshot()` API.
    private var _snapshot = RawActivitySnapshot()

    /// Coalesced activity notification, delivered on the main thread at most once per second.
    var onActivity: (() -> Void)?

    /// Called on the main thread when permissions appear to be missing.
    var onPermissionOrTapFailure: ((String) -> Void)?

    /// Called on the main thread when event monitoring is successfully started.
    var onPermissionGranted: (() -> Void)?

    private let logger = Logger(subsystem: "com.tendontally", category: "EventTapManager")
    private var retryTimer: Timer?
    private var retryDelay: TimeInterval = 3
    private var hasRegisteredMonitors = false

    /// Start monitoring events. If no events are received (permissions missing), retries periodically.
    func start() {
        DispatchQueue.main.async { [weak self] in
            self?.registerMonitors()
        }
    }

    private func registerMonitors() {
        guard !hasRegisteredMonitors else { return }

        // NSEvent global monitors can fail silently when permissions are missing.
        // Probe both required permissions before registering monitors.
        let status = Self.probePermissionStatus()
        logger.info("Permission probe - Accessibility: \(status.accessibilityGranted), Input Monitoring: \(status.inputMonitoringGranted)")

        if !status.allRequiredGranted {
            handleRegistrationFailure(message: status.guidanceMessage)
            return
        }

        stopRetryTimer()
        retryDelay = 3
        logger.info("Registering NSEvent monitors...")
        var failedGlobalMasks: [UInt64] = []

        // Key down — filter out auto-repeat so holding a key counts as one stroke
        let keyHandler: (NSEvent) -> NSEvent? = { [weak self] event in
            if !event.isARepeat {
                self?.recordActivity { snapshot in
                    snapshot.keyPressCount += 1
                }
            }
            return event
        }
        if !addMonitors(matching: .keyDown, handler: keyHandler).global {
            failedGlobalMasks.append(NSEvent.EventTypeMask.keyDown.rawValue)
        }

        // Mouse clicks
        let leftClickHandler: (NSEvent) -> NSEvent? = { [weak self] event in
            self?.recordActivity { snapshot in
                snapshot.mouseClickCount += 1
            }
            return event
        }
        if !addMonitors(matching: .leftMouseDown, handler: leftClickHandler).global {
            failedGlobalMasks.append(NSEvent.EventTypeMask.leftMouseDown.rawValue)
        }

        let rightClickHandler: (NSEvent) -> NSEvent? = { [weak self] event in
            self?.recordActivity { snapshot in
                snapshot.mouseClickCount += 1
            }
            return event
        }
        if !addMonitors(matching: .rightMouseDown, handler: rightClickHandler).global {
            failedGlobalMasks.append(NSEvent.EventTypeMask.rightMouseDown.rawValue)
        }

        let otherClickHandler: (NSEvent) -> NSEvent? = { [weak self] event in
            self?.recordActivity { snapshot in
                snapshot.mouseClickCount += 1
            }
            return event
        }
        if !addMonitors(matching: .otherMouseDown, handler: otherClickHandler).global {
            failedGlobalMasks.append(NSEvent.EventTypeMask.otherMouseDown.rawValue)
        }

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
                self?.recordActivity { snapshot in
                    snapshot.scrollTicks += magnitude
                }
            }
            return event
        }
        if !addMonitors(matching: .scrollWheel, handler: scrollHandler).global {
            failedGlobalMasks.append(NSEvent.EventTypeMask.scrollWheel.rawValue)
        }

        // Mouse movement
        let moveHandler: (NSEvent) -> NSEvent? = { [weak self] event in
            let location = NSEvent.mouseLocation
            self?.recordActivity { [weak self] snapshot in
                guard let self else { return }
                if let last = lastMouseLocation {
                    let dx = Double(location.x - last.x)
                    let dy = Double(location.y - last.y)
                    let distance = (dx * dx + dy * dy).squareRoot()
                    snapshot.mouseDistance += distance
                }
                lastMouseLocation = location
            }
            return event
        }
        if !addMonitors(matching: .mouseMoved, handler: moveHandler).global {
            failedGlobalMasks.append(NSEvent.EventTypeMask.mouseMoved.rawValue)
        }

        // Mouse dragging (also counts as movement)
        let dragHandler: (NSEvent) -> NSEvent? = { [weak self] event in
            let location = NSEvent.mouseLocation
            self?.recordActivity { [weak self] snapshot in
                guard let self else { return }
                if let last = lastMouseLocation {
                    let dx = Double(location.x - last.x)
                    let dy = Double(location.y - last.y)
                    let distance = (dx * dx + dy * dy).squareRoot()
                    snapshot.mouseDistance += distance
                }
                lastMouseLocation = location
            }
            return event
        }
        if !addMonitors(matching: .leftMouseDragged, handler: dragHandler).global {
            failedGlobalMasks.append(NSEvent.EventTypeMask.leftMouseDragged.rawValue)
        }
        if !addMonitors(matching: .rightMouseDragged, handler: dragHandler).global {
            failedGlobalMasks.append(NSEvent.EventTypeMask.rightMouseDragged.rawValue)
        }

        if !failedGlobalMasks.isEmpty {
            let failedMasksDescription = failedGlobalMasks.map(String.init).joined(separator: ", ")
            logger.error("Required global monitors failed to register for masks: \(failedMasksDescription)")
            handleRegistrationFailure(
                message: "TendonTally could not start global input monitoring. Re-enable Accessibility and Input Monitoring permissions, then relaunch TendonTally."
            )
            return
        }

        hasRegisteredMonitors = true
        onPermissionGranted?()
    }

    @discardableResult
    private func addMonitors(matching mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> NSEvent?) -> (global: Bool, local: Bool) {
        var globalAdded = false
        var localAdded = false

        // Global monitor: events in other apps. Handler returns Void (can't modify events).
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { event in
            _ = handler(event)
        }) {
            globalMonitors.append(global)
            globalAdded = true
            logger.info("Global monitor registered for mask: \(mask.rawValue)")
        } else {
            logger.error("Failed to register global monitor for mask: \(mask.rawValue)")
        }

        // Local monitor: events in this app. Handler can return modified event.
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: handler) {
            localMonitors.append(local)
            localAdded = true
            logger.info("Local monitor registered for mask: \(mask.rawValue)")
        } else {
            logger.error("Failed to register local monitor for mask: \(mask.rawValue)")
        }

        return (global: globalAdded, local: localAdded)
    }

    private func handleRegistrationFailure(message: String) {
        removeAllMonitors()
        hasRegisteredMonitors = false
        onPermissionOrTapFailure?(message)
        startRetryTimer()
    }

    private func removeAllMonitors() {
        for monitor in globalMonitors {
            NSEvent.removeMonitor(monitor)
        }
        globalMonitors.removeAll()

        for monitor in localMonitors {
            NSEvent.removeMonitor(monitor)
        }
        localMonitors.removeAll()
    }

    static func probePermissionStatus() -> PermissionStatus {
        PermissionStatus(
            accessibilityGranted: isAccessibilityGranted(),
            inputMonitoringGranted: isInputMonitoringGranted()
        )
    }

    static func isAccessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }

    static func isInputMonitoringGranted() -> Bool {
        if #available(macOS 10.15, *) {
            return CGPreflightListenEventAccess()
        }

        let probeMask: CGEventMask = 1 << CGEventMask(CGEventType.keyDown.rawValue)
        guard let probe = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: probeMask,
            callback: { _, _, event, _ in
                Unmanaged.passUnretained(event)
            },
            userInfo: nil
        ) else {
            return false
        }

        CFMachPortInvalidate(probe)
        return true
    }

    private func startRetryTimer() {
        guard retryTimer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: retryDelay, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.retryTimer = nil
            self.registerMonitors()
        }
        timer.tolerance = min(30, retryDelay / 2)
        retryTimer = timer
        retryDelay = min(5 * 60, retryDelay * 2)
        RunLoop.main.add(timer, forMode: .common)
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
        removeAllMonitors()
        hasRegisteredMonitors = false
        stateLock.lock()
        lastMouseLocation = nil
        _snapshot = RawActivitySnapshot()
        activityNotificationScheduled = false
        activityNotificationGeneration += 1
        stateLock.unlock()
    }

    /// Thread-safe snapshot of the current raw activity counts.
    func snapshot() -> RawActivitySnapshot {
        stateLock.lock()
        let result = _snapshot
        stateLock.unlock()
        return result
    }

    /// Reset the raw counters (used when rolling to a new window).
    /// Synchronous so that the next snapshot() call reads zeroes.
    func resetCounters() {
        stateLock.lock()
        let lastActivityAt = _snapshot.lastActivityAt
        _snapshot = RawActivitySnapshot()
        _snapshot.lastActivityAt = lastActivityAt
        stateLock.unlock()
    }

    /// Mutates counters directly under a short lock instead of enqueuing one block per HID event.
    /// The UI/domain notification is trailing-edge coalesced, so rapid mouse input produces at
    /// most one main-thread update per second while the raw counters remain exact.
    private func recordActivity(_ update: (inout RawActivitySnapshot) -> Void) {
        stateLock.lock()
        update(&_snapshot)
        _snapshot.lastActivityAt = Date()
        let shouldScheduleNotification = !activityNotificationScheduled
        let generation: Int
        if shouldScheduleNotification {
            activityNotificationScheduled = true
            activityNotificationGeneration += 1
        }
        generation = activityNotificationGeneration
        stateLock.unlock()

        guard shouldScheduleNotification else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self else { return }
            self.stateLock.lock()
            guard generation == self.activityNotificationGeneration else {
                self.stateLock.unlock()
                return
            }
            self.activityNotificationScheduled = false
            let callback = self.onActivity
            self.stateLock.unlock()
            callback?()
        }
    }
}
