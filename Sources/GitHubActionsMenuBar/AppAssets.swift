import AppKit

@MainActor
struct AppAssets {
    static var menuBarIcon: NSImage? {
        return NSImage(named: "MenuBarIcon")
    }

    static var applicationIcon: NSImage? {
        return NSImage(named: "ApplicationIcon")
    }
}