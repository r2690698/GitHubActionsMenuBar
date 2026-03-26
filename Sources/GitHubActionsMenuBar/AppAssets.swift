import AppKit
import SwiftUI

enum AppAssets {
    static let menuBarIcon: NSImage = {
        let image = NSImage(
            contentsOf: Bundle.module.url(forResource: "GitHub_Invertocat_Black", withExtension: "pdf")!
        )!
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }()

    static let applicationIcon: NSImage? = {
        guard let path = Bundle.main.path(forResource: "AppIcon", ofType: "icns") else {
            return nil
        }

        return NSImage(contentsOfFile: path)
    }()

    static func menuBarStatusImage(primaryColor: NSColor, badgeSymbol: String) -> NSImage {
        let size = NSSize(width: 20, height: 18)
        let image = NSImage(size: size)

        image.lockFocus()
        defer { image.unlockFocus() }

        let baseRect = NSRect(x: 1, y: 0, width: 16, height: 16)
        menuBarIcon.draw(in: baseRect)

        let badgeRect = NSRect(x: 10, y: 0, width: 10, height: 10)
        let badgePath = NSBezierPath(ovalIn: badgeRect)
        NSColor.windowBackgroundColor.setFill()
        badgePath.fill()

        let innerBadgeRect = badgeRect.insetBy(dx: 1, dy: 1)
        let innerBadgePath = NSBezierPath(ovalIn: innerBadgeRect)
        primaryColor.setFill()
        innerBadgePath.fill()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 6, weight: .bold),
            .foregroundColor: NSColor.white
        ]

        let attributedString = NSAttributedString(string: badgeSymbol, attributes: attributes)
        let textSize = attributedString.size()
        let textOrigin = NSPoint(
            x: innerBadgeRect.midX - (textSize.width / 2),
            y: innerBadgeRect.midY - (textSize.height / 2) - 0.5
        )
        attributedString.draw(at: textOrigin)

        image.isTemplate = false
        return image
    }
}

struct GitHubLockupView: View {
    var body: some View {
        Image("GitHub_Lockup_Black", bundle: .module)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
    }
}
