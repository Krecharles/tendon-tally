import AppKit
import SwiftUI

/// Manages the menu bar status item and the SwiftUI-based popover dashboard.
///
/// This controller handles the creation and lifecycle of the NSStatusItem that appears
/// in the macOS menu bar, and manages the popover that displays the compact dashboard view.
final class StatusItemController {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let viewModel: MetricsViewModel

    init(viewModel: MetricsViewModel) {
        self.viewModel = viewModel
    }

    func setupStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "cursorarrow.motionlines", accessibilityDescription: "TendonTally")
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        self.statusItem = statusItem

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 400, height: 450)
        popover.contentViewController = NSHostingController(rootView: DashboardView(viewModel: viewModel))
    }

    func tearDown() {
        if let statusItem = statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        if popover.isShown {
            popover.performClose(sender)
        } else if let button = statusItem?.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.becomeKey()
        }
    }
}

