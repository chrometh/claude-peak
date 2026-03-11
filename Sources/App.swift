import SwiftUI
import AppKit
import Combine

@main
struct ClaudePeakApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var service: UsageService!
    private var settings: AppSettings!
    private var activity: ActivityMonitor!

    private var animationTimer: Timer?
    private var displayTimer: Timer?
    private var frameIndex = 0
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.info("Claude Peak launched")
        service = UsageService()
        settings = AppSettings.shared
        activity = ActivityMonitor()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        popover = NSPopover()
        popover.contentSize = NSSize(width: 280, height: 400)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: UsageView(service: service, settings: settings, activity: activity)
                .frame(width: 280)
        )

        if let button = statusItem.button {
            button.action = #selector(togglePopover)
            button.target = self
        }

        updateMenuBar()

        displayTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateMenuBar()
            }
        }

        activity.$tokensPerSecond.sink { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateAnimationSpeed()
            }
        }.store(in: &cancellables)

        settings.$flameMode.sink { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateMenuBar()
                self?.updateAnimationSpeed()
            }
        }.store(in: &cancellables)

        service.startPolling()
        activity.start()
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - Flame Rendering

    private func flameCount(for tps: Double) -> Int {
        switch settings.flameMode {
        case .off:
            return 0
        case .single:
            return tps > 0 ? 1 : 0
        case .dynamic:
            if tps > 60000 { return 3 }
            if tps > 30000 { return 2 }
            if tps > 0     { return 1 }
            return 0
        case .madmax:
            if tps <= 0 { return 0 }
            return min(10, Int(tps / 10000) + 1)
        }
    }

    private func createFlameImage(count: Int, frame: Int) -> NSImage {
        let size: CGFloat = 18
        let overlap: CGFloat = 0
        let totalWidth = count == 0 ? size : size + CGFloat(count - 1) * (size - overlap)

        let image = NSImage(size: NSSize(width: totalWidth, height: size))
        image.lockFocus()

        for i in 0..<count {
            // Each sparkle flickers independently using offset frame
            let flicker = (frame + i * 2) % 4
            let pointSize: CGFloat

            switch flicker {
            case 0:  pointSize = 16
            case 1:  pointSize = 14
            case 2:  pointSize = 15
            default: pointSize = 17
            }

            let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
            if let symbol = NSImage(systemSymbolName: "sparkle", accessibilityDescription: nil)?
                .withSymbolConfiguration(config) {
                let x = CGFloat(i) * (size - overlap)
                let yOffset = (size - pointSize) / 2
                symbol.draw(in: NSRect(x: x, y: yOffset, width: pointSize, height: pointSize))
            }
        }

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    // MARK: - Update

    private func colorForPercentage(_ pct: Int) -> NSColor {
        if pct >= 80 { return .systemRed }
        if pct >= 50 { return .systemOrange }
        return .systemGreen
    }

    private func createProgressBarImage(percentage: Int, text: String) -> NSImage {
        // The border is a ring AROUND the color bar.
        // We size the image to fit: border ring + gap + inner color pill.
        let barHeight: CGFloat = 20
        let horizontalPadding: CGFloat = 12
        let borderThickness: CGFloat = 1.5
        let textFont = NSFont.menuBarFont(ofSize: 0)

        let textColor: NSColor = NSAppearance.currentDrawing().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? .white
            : .black

        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: textFont,
            .foregroundColor: textColor
        ]
        let textSize = (text as NSString).size(withAttributes: textAttrs)
        let barWidth = textSize.width + horizontalPadding * 2

        let image = NSImage(size: NSSize(width: barWidth, height: barHeight))
        image.lockFocus()

        let outerRadius = barHeight / 2
        let outerRect = NSRect(x: 0, y: 0, width: barWidth, height: barHeight)
        let innerRect = outerRect.insetBy(dx: borderThickness, dy: borderThickness)
        let innerRadius = outerRadius - borderThickness
        let innerPath = NSBezierPath(roundedRect: innerRect, xRadius: innerRadius, yRadius: innerRadius)

        // 1) Track background (drawn first, behind everything)
        textColor.withAlphaComponent(0.1).setFill()
        innerPath.fill()

        // 2) Color fill — clipped to inner pill so it fits perfectly against the border
        let fillWidth = innerRect.width * min(1, CGFloat(percentage) / 100)

        if fillWidth > 0 {
            NSGraphicsContext.saveGraphicsState()
            innerPath.addClip()

            let fillRect = NSRect(x: innerRect.origin.x, y: innerRect.origin.y,
                                  width: fillWidth, height: innerRect.height)
            colorForPercentage(percentage).setFill()
            NSBezierPath.fill(fillRect)

            NSGraphicsContext.restoreGraphicsState()
        }

        // 3) Text
        let textDrawColor: NSColor = percentage >= 40 ? .white : textColor
        let textDrawAttrs: [NSAttributedString.Key: Any] = [
            .font: textFont,
            .foregroundColor: textDrawColor
        ]

        let textX = (barWidth - textSize.width) / 2
        let capHeight = textFont.capHeight
        let textY = (barHeight - capHeight) / 2 - (textFont.ascender - capHeight)
        (text as NSString).draw(at: NSPoint(x: textX, y: textY), withAttributes: textDrawAttrs)

        // 4) Border ring — drawn LAST so it's always on top of the fill
        let borderPath = NSBezierPath(roundedRect: outerRect.insetBy(dx: borderThickness / 2, dy: borderThickness / 2),
                                       xRadius: outerRadius - borderThickness / 2,
                                       yRadius: outerRadius - borderThickness / 2)
        borderPath.lineWidth = borderThickness
        NSColor.labelColor.setStroke()
        borderPath.stroke()

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private func updateMenuBar() {
        guard let button = statusItem.button else { return }

        // Sparkle/flame icon — stays as template (adapts to menu bar appearance)
        if settings.flameMode != .off {
            let tps = activity.tokensPerSecond
            let count = flameCount(for: tps)

            if count > 0 {
                button.image = createFlameImage(count: count, frame: frameIndex)
            } else {
                let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
                let image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: "usage")?
                    .withSymbolConfiguration(config)
                image?.isTemplate = true
                button.image = image
            }
        } else {
            button.image = nil
        }

        guard let usage = service.usage else {
            button.attributedTitle = NSAttributedString(string: " —")
            button.title = ""
            return
        }

        let pct = usage.fiveHour.percentage
        let resetTime = usage.fiveHour.timeUntilReset

        // Build display text for inside the bar
        let displayText: String
        switch settings.menuBarDisplay {
        case .percentOnly:  displayText = "\(pct)%"
        case .timeOnly:     displayText = resetTime
        case .both:         displayText = "\(pct)% · \(resetTime)"
        }

        // Progress bar as text attachment (keeps sparkle icon separate as template)
        let barImage = createProgressBarImage(percentage: pct, text: displayText)
        let attachment = NSTextAttachment()
        attachment.image = barImage
        let yOffset = -6.5
        attachment.bounds = CGRect(x: 0, y: yOffset, width: barImage.size.width, height: barImage.size.height)

        let attrString = NSMutableAttributedString(string: " ")
        attrString.append(NSAttributedString(attachment: attachment))
        button.title = ""
        button.attributedTitle = attrString
    }

    private func animationInterval(for tps: Double) -> TimeInterval? {
        guard tps > 0 else { return nil }

        if settings.flameMode == .madmax {
            // 0.40s at low tps → 0.06s at 50000+
            let t = min(tps / 50000, 1.0)
            return 0.40 - t * 0.34
        }

        if tps > 60000 {
            // 3 flames: 0.20s → 0.08s
            let t = min((tps - 60000) / 40000, 1.0)
            return 0.20 - t * 0.12
        } else if tps > 30000 {
            // 2 flames: 0.30s → 0.15s
            let t = (tps - 30000) / 30000
            return 0.30 - t * 0.15
        } else {
            // 1 flame: 0.50s → 0.20s
            let t = min(tps / 30000, 1.0)
            return 0.50 - t * 0.30
        }
    }

    private func updateAnimationSpeed() {
        animationTimer?.invalidate()
        animationTimer = nil

        guard settings.flameMode != .off else { return }

        let tps = activity.tokensPerSecond
        guard let interval = animationInterval(for: tps) else { return }

        animationTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.frameIndex += 1
                self?.updateMenuBar()
            }
        }
    }
}
