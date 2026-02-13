import AppKit
import SwiftUI

private let pillWidth: CGFloat = 440
private let pillHeight: CGFloat = 74

/// Borderless floating panel that hosts the break pill SwiftUI view.
final class BreakPillPanel: NSPanel {
    @MainActor
    init(controller: BreakPillController, screen: NSScreen) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: pillWidth, height: pillHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )

        level = .floating
        isOpaque = false
        backgroundColor = .clear
        isMovableByWindowBackground = true
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let hostingView = NSHostingView(
            rootView: BreakPillView(controller: controller)
                .frame(width: pillWidth, height: pillHeight)
        )
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        contentView = hostingView

        positionAtTopCenter(of: screen)
    }

    func showPill() {
        guard !isVisible else { return }
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }
    }

    func hidePill() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        }, completionHandler: {
            self.orderOut(nil)
        })
    }

    private func positionAtTopCenter(of screen: NSScreen) {
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - frame.width / 2
        let y = screenFrame.maxY - frame.height - 12
        setFrameOrigin(NSPoint(x: x, y: y))
    }
}

// MARK: - SwiftUI Pill View

struct BreakPillView: View {
    @ObservedObject var controller: BreakPillController
    @State private var celebrationScale: CGFloat = 0
    @State private var glowPulsing: Bool = false

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 12) {
                Image("app-icon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 22, height: 22)

                Text(phaseLabel)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)

                Text(controller.primaryText)
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: controller.primaryText)

                if controller.phase == .onBreak || controller.phase == .due {
                    ProgressView(value: controller.progress)
                        .progressViewStyle(.linear)
                        .frame(width: 80)
                        .tint(phaseColor)
                        .animation(.linear(duration: 0.8), value: controller.progress)
                }

                if controller.showCelebration {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.green)
                        .scaleEffect(celebrationScale)
                        .onAppear {
                            celebrationScale = 0
                            glowPulsing = false
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) {
                                celebrationScale = 1
                            }
                            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true).delay(0.3)) {
                                glowPulsing = true
                            }
                        }
                        .onDisappear {
                            celebrationScale = 0
                            glowPulsing = false
                        }
                }
            }

            if controller.showResetWarning {
                Text("Any input resets the timer")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: controller.showResetWarning)
        .animation(.default, value: controller.showCelebration)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(Color.green.opacity(glowPulsing ? 0.6 : 0), lineWidth: 1.5)
        )
    }

    private var phaseLabel: String {
        switch controller.phase {
        case .work: return "Working"
        case .due: return "Break due"
        case .onBreak: return "Break complete"
        }
    }

    private var phaseColor: Color {
        switch controller.phase {
        case .work: return .green
        case .due: return .orange
        case .onBreak: return .blue
        }
    }
}
