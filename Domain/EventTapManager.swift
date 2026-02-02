import Foundation
import Cocoa
import CoreGraphics

/// Manages a global CGEvent tap and updates a RawActivitySnapshot as events arrive.
/// 
/// This class monitors keyboard and mouse events system-wide using CoreGraphics event taps.
/// It tracks key presses, mouse clicks, scroll events, and mouse movement distance.
/// All tracking is passive (listen-only) and does not record key contents, only counts.
/// Inspired by OctoMouse's use of CGEventTap to track keyboard and mouse activity:
/// https://github.com/KonsomeJona/OctoMouse
final class EventTapManager {
    private let eventMask: CGEventMask
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private let queue = DispatchQueue(label: "ActivityTracker.EventTapManager")
    private var lastMouseLocation: CGPoint?

    /// Current snapshot is updated on `queue` and read via `snapshot()` API.
    private var _snapshot = RawActivitySnapshot()

    /// Called on the main thread when permissions appear to be missing or the tap is disabled by the system.
    var onPermissionOrTapFailure: ((String) -> Void)?

    init() {
        var mask: CGEventMask = 0
        func addMask(_ type: CGEventType) {
            mask |= (1 << CGEventMask(type.rawValue))
        }
        addMask(.keyDown)
        addMask(.leftMouseDown)
        addMask(.rightMouseDown)
        addMask(.otherMouseDown)
        addMask(.scrollWheel)
        addMask(.mouseMoved)
        addMask(.leftMouseDragged)
        addMask(.rightMouseDragged)
        self.eventMask = mask
    }

    /// Start the global event tap.
    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            if self.eventTap != nil { return }

            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: self.eventMask,
                callback: { proxy, type, event, refcon in
                    guard let refcon else { return Unmanaged.passUnretained(event) }
                    let unmanaged = Unmanaged<EventTapManager>.fromOpaque(refcon)
                    let manager = unmanaged.takeUnretainedValue()
                    return manager.handleEvent(proxy: proxy, type: type, event: event)
                },
                userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
            )

            guard let eventTap = tap else {
                DispatchQueue.main.async {
                    self.onPermissionOrTapFailure?("Unable to create event tap. Check Accessibility / Input Monitoring permissions.")
                }
                return
            }

            self.eventTap = eventTap
            if let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) {
                self.runLoopSource = source
                CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
                CGEvent.tapEnable(tap: eventTap, enable: true)
            } else {
                DispatchQueue.main.async {
                    self.onPermissionOrTapFailure?("Unable to create run loop source for event tap.")
                }
            }
        }
    }

    /// Stop and remove the event tap.
    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            if let source = self.runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
                self.runLoopSource = nil
            }
            if let tap = self.eventTap {
                CGEvent.tapEnable(tap: tap, enable: false)
                self.eventTap = nil
            }
            self.lastMouseLocation = nil
            self._snapshot = RawActivitySnapshot()
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
    func resetCounters() {
        queue.async { [weak self] in
            self?._snapshot = RawActivitySnapshot()
        }
    }

    // MARK: - Event Handling

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent> {
        // If the event tap is disabled by the system (e.g. permissions changed), notify the UI.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            DispatchQueue.main.async { [weak self] in
                // Keep this message short; detailed instructions are shown in the UI banner.
                self?.onPermissionOrTapFailure?("Event tap disabled by the system.")
            }
            // Re-enable the tap if possible.
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        queue.async { [weak self] in
            guard let self else { return }
            switch type {
            case .keyDown:
                self._snapshot.keyPressCount += 1

            case .leftMouseDown, .rightMouseDown, .otherMouseDown:
                self._snapshot.mouseClickCount += 1

            case .scrollWheel:
                // Only count scroll ticks; ignore pixel-based distance.
                let deltaY = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
                let magnitude = abs(deltaY)
                if magnitude > 0 {
                    self._snapshot.scrollTicks += Int(magnitude)
                }

            case .mouseMoved, .leftMouseDragged, .rightMouseDragged:
                let location = event.location
                if let last = self.lastMouseLocation {
                    let dx = Double(location.x - last.x)
                    let dy = Double(location.y - last.y)
                    let distance = (dx * dx + dy * dy).squareRoot()
                    self._snapshot.mouseDistance += distance
                }
                self.lastMouseLocation = location

            default:
                break
            }
        }

        // We are a passive listener (listenOnly), so return the original event unmodified.
        return Unmanaged.passUnretained(event)
    }
}

