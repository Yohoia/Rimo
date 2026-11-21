import AppKit
import CoreText
import SwiftUI

@main
struct RimoApp: App {
    @NSApplicationDelegateAdaptor(RimoAppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            RimoMenu(model: delegate.model, openSettings: delegate.showSettings)
        } label: {
            Image("MenuBarIcon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .accessibilityLabel("Rimo")
        }
    }
}

private struct RimoMenu: View {
    @ObservedObject var model: RimoModel
    let openSettings: () -> Void

    var body: some View {
        Text(model.statusTitle)
        if model.voice.installed && model.voice.wanted {
            // Voxa's menu bar shows the voice chain and offers a repair.
            Text("语音：\(model.voice.state.title)")
            if case .failed = model.voice.state {
                Button("修复语音…") { model.voice.repair() }
            }
        }
        Button("打开按键设置…", action: openSettings)
        Toggle("滚动模式", isOn: Binding(get: { model.scrollMode.enabled }, set: { _ in model.toggleScrollMode() }))
        Button(model.paused ? "恢复映射" : "暂停映射") { model.togglePaused() }
        Divider()
        Button("退出 Rimo") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

@MainActor
final class RimoAppDelegate: NSObject, NSApplicationDelegate {
    let model = RimoModel()
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
            window.title = "Rimo · 遥控器设置"
            window.isReleasedWhenClosed = false
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.contentMinSize = NSSize(width: 860, height: 600)
            window.contentView = NSHostingView(rootView: RimoSettingsView(model: model))
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
