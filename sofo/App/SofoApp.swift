import AppKit
import CoreText
import SwiftUI

@main
struct SofoApp: App {
    @NSApplicationDelegateAdaptor(SofoAppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            SofoMenu(model: delegate.model, openSettings: delegate.showSettings)
        } label: {
            if let icon = NSImage(named: "MenuBarIcon") {
                Image(nsImage: icon)
                    .renderingMode(.template)
                    .accessibilityLabel("sofo")
            } else {
                Image(systemName: "appletvremote.gen4")
                    .accessibilityLabel("sofo")
            }
        }
    }
}

private struct SofoMenu: View {
    @ObservedObject var model: SofoModel
    let openSettings: () -> Void

    var body: some View {
        Text(model.statusTitle)
        Button("打开按键设置…", action: openSettings)
        Button(model.paused ? "恢复映射" : "暂停映射") { model.togglePaused() }
        Divider()
        Text(model.voice.state.title)
        Button(model.voice.enabled ? "停止遥控器收音" : "启用遥控器收音…") {
            if model.voice.enabled { model.voice.stop() } else { model.voice.start() }
        }
        Divider()
        Button("退出 sofo") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

@MainActor
final class SofoAppDelegate: NSObject, NSApplicationDelegate {
    let model = SofoModel()
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        for name in ["Geist-Regular", "Geist-Medium", "GeistMono-Regular"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "Geist") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
        showSettings()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showSettings()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }

    func showSettings() {
        model.refresh()
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1200, height: 720),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "sofo · 遥控器设置"
            window.isReleasedWhenClosed = false
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.contentMinSize = NSSize(width: 860, height: 600)
            window.contentView = NSHostingView(rootView: SofoSettingsView(model: model))
            model.isSettingsFocused = { [weak window] in
                window?.isKeyWindow == true || window?.attachedSheet?.isKeyWindow == true
            }
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        if settingsWindow?.isMiniaturized == true {
            settingsWindow?.deminiaturize(nil)
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
