import AppKit
import SwiftUI

@main
struct GitHubActionsMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = GitHubActionsStore()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(store: store)
                .task {
                    await store.start()
                }
        } label: {
            MenuBarLabelView(store: store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(store: store)
                .frame(width: 420, height: 280)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--self-test") {
            let failures = GitHubActionsMenuBarSelfTestSuite.run()
            if failures.isEmpty {
                print("All self-tests passed.")
                NSApp.terminate(nil)
                return
            }

            for failure in failures {
                fputs("FAIL: \(failure)\n", stderr)
            }
            Foundation.exit(EXIT_FAILURE)
        }

        NSApp.setActivationPolicy(.accessory)
        if let applicationIcon = AppAssets.applicationIcon {
            NSApplication.shared.applicationIconImage = applicationIcon
        }
    }
}

private struct MenuBarLabelView: View {
    let store: GitHubActionsStore

    var body: some View {
        Image(
            nsImage: AppAssets.menuBarStatusImage(
                primaryColor: NSColor(store.menuBarPrimaryColor),
                badgeSymbol: store.menuBarStatusBadgeGlyph
            )
        )
    }
}
