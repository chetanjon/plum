import AppKit
import ApplicationServices

/// Moves the frontmost app's focused window by voice: halves, fill,
/// center. Accessibility is the one permission this needs; without it
/// the reply says so and the system prompt is raised once.
@MainActor
enum WindowSnapper {
    enum Position {
        case left
        case right
        case full
        case center
    }

    static func snap(_ position: Position) -> String {
        guard AXIsProcessTrusted() else {
            let options = [
                kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true,
            ] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
            return "Moving windows needs Accessibility."
                + " System Settings, Privacy, Accessibility, switch on Plum, then say it again."
        }
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return "No app in front."
        }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var windowRef: CFTypeRef?
        let copied = AXUIElementCopyAttributeValue(
            axApp, kAXFocusedWindowAttribute as CFString, &windowRef
        )
        guard copied == .success, let ref = windowRef, CFGetTypeID(ref) == AXUIElementGetTypeID() else {
            return "\(app.localizedName ?? "That app") has no window to move."
        }
        let window = unsafeDowncast(ref, to: AXUIElement.self)

        let screen = screenOf(window) ?? NSScreen.main
        guard let screen else { return "No screen to place it on." }
        let vis = screen.visibleFrame

        let target: NSRect
        switch position {
        case .left:
            target = NSRect(x: vis.minX, y: vis.minY, width: vis.width / 2, height: vis.height)
        case .right:
            target = NSRect(x: vis.midX, y: vis.minY, width: vis.width / 2, height: vis.height)
        case .full:
            target = vis
        case .center:
            target = NSRect(
                x: vis.minX + vis.width * 0.15,
                y: vis.minY + vis.height * 0.10,
                width: vis.width * 0.70,
                height: vis.height * 0.80
            )
        }

        apply(target, to: window)

        let name = app.localizedName ?? "Window"
        switch position {
        case .left: return "\(name), left half."
        case .right: return "\(name), right half."
        case .full: return "\(name), filled."
        case .center: return "\(name), centered."
        }
    }

    /// AX speaks top-left global coordinates; AppKit speaks bottom-left.
    /// The primary screen's height is the conversion constant.
    private static var primaryMaxY: CGFloat {
        NSScreen.screens.first?.frame.maxY ?? 0
    }

    private static func apply(_ frame: NSRect, to window: AXUIElement) {
        var origin = CGPoint(x: frame.minX, y: primaryMaxY - frame.maxY)
        var size = CGSize(width: frame.width, height: frame.height)
        guard let positionValue = AXValueCreate(.cgPoint, &origin),
              let sizeValue = AXValueCreate(.cgSize, &size) else { return }
        // Size, position, size: apps with minimum sizes settle wrong
        // when the window crosses screens unless size lands first and
        // again after the move.
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
    }

    /// The screen holding the window's center, so snapping respects
    /// wherever the window already lives.
    private static func screenOf(_ window: AXUIElement) -> NSScreen? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success
        else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard let positionValue = positionRef, CFGetTypeID(positionValue) == AXValueGetTypeID(),
              let sizeValue = sizeRef, CFGetTypeID(sizeValue) == AXValueGetTypeID(),
              AXValueGetValue(unsafeDowncast(positionValue, to: AXValue.self), .cgPoint, &origin),
              AXValueGetValue(unsafeDowncast(sizeValue, to: AXValue.self), .cgSize, &size)
        else { return nil }
        // Back to bottom-left space for the screen lookup.
        let center = CGPoint(
            x: origin.x + size.width / 2,
            y: primaryMaxY - (origin.y + size.height / 2)
        )
        return NSScreen.screens.first { $0.frame.contains(center) }
    }
}
