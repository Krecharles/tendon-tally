import AppKit
import SwiftUI

/// Manages the menu bar status item and the SwiftUI-based popover dashboard.
///
/// This controller handles the creation and lifecycle of the NSStatusItem that appears
/// in the macOS menu bar, and manages the popover that displays the compact dashboard view.
@MainActor
final class StatusItemController: NSObject {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let viewModel: MetricsViewModel
    private let quickActionsMenu = NSMenu()
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?

    init(viewModel: MetricsViewModel) {
        self.viewModel = viewModel
        super.init()
    }

    func setupStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            // Use custom icon from asset catalog
            if let customIcon = NSImage(named: "menubar-icon") {
                customIcon.isTemplate = true // Makes it adapt to light/dark mode
                button.image = customIcon
            } else {
                // Fallback to SF Symbol if asset not found
                button.image = NSImage(systemSymbolName: "cursorarrow.motionlines", accessibilityDescription: "TendonTally")
            }
            button.action = #selector(togglePopover(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        self.statusItem = statusItem
        configureQuickActionsMenu()

        popover.behavior = .transient
        popover.delegate = self
        popover.contentSize = NSSize(width: 340, height: 400)
        popover.contentViewController = NSHostingController(rootView: DashboardView(viewModel: viewModel))
    }

    func tearDown() {
        stopClickMonitoring()
        if let statusItem = statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            showQuickActionsMenu(using: event)
            return
        }

        if popover.isShown {
            closePopover(sender)
        } else if let button = statusItem?.button {
            showPopover(relativeTo: button)
        }
    }

    private func configureQuickActionsMenu() {
        let copyTodayItem = NSMenuItem(
            title: "Copy Today Metrics",
            action: #selector(copyTodayMetrics),
            keyEquivalent: ""
        )
        copyTodayItem.target = self
        quickActionsMenu.addItem(copyTodayItem)

        let copyYesterdayItem = NSMenuItem(
            title: "Copy Yesterday Metrics",
            action: #selector(copyYesterdayMetrics),
            keyEquivalent: ""
        )
        copyYesterdayItem.target = self
        quickActionsMenu.addItem(copyYesterdayItem)
    }

    private func showQuickActionsMenu(using event: NSEvent) {
        closePopover(nil)
        guard let button = statusItem?.button else { return }
        NSMenu.popUpContextMenu(quickActionsMenu, with: event, for: button)
    }

    @objc
    private func copyTodayMetrics() {
        copyMetrics(for: .today)
    }

    @objc
    private func copyYesterdayMetrics() {
        copyMetrics(for: .yesterday)
    }

    private func copyMetrics(for day: DailyExportDay) {
        if viewModel.copyDailyMetricsToClipboard(for: day) == nil {
            NSSound.beep()
        }
    }

    private func showPopover(relativeTo button: NSStatusBarButton) {
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.becomeKey()
        startClickMonitoring()
    }

    private func closePopover(_ sender: AnyObject?) {
        popover.performClose(sender)
        stopClickMonitoring()
    }

    private func startClickMonitoring() {
        stopClickMonitoring()

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async {
                self.closePopover(nil)
            }
        }

        localClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            guard let self else { return event }
            guard self.popover.isShown else { return event }

            let popoverWindow = self.popover.contentViewController?.view.window
            if event.window !== popoverWindow {
                self.closePopover(nil)
            }

            return event
        }
    }

    private func stopClickMonitoring() {
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
        }
        if let monitor = localClickMonitor {
            NSEvent.removeMonitor(monitor)
            localClickMonitor = nil
        }
    }
}

extension StatusItemController: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        stopClickMonitoring()
    }
}
