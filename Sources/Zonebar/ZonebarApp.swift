import AppKit
import SwiftUI

@main
struct ZonebarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var timeZoneStore = TimeZoneStore(zones: TrackedTimeZone.defaults)

    var body: some Scene {
        MenuBarExtra {
            ZoneMenuContentView(store: timeZoneStore)
        } label: {
            Text(timeZoneStore.menuBarTitle)
                .font(AppFont.uiFont(size: 13, weight: .medium))
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}
