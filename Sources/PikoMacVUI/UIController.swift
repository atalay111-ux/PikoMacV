import AppKit
import SwiftUI
import PikoMacVKit

private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void
    init(_ title: String, _ handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func fire() { handler() }
}

@MainActor
public final class UIController {
    private let state: AppState
    private let core: CoreActions
    private let input: InputActions
    private var statusItem: NSStatusItem?
    private var panelController: PanelController
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    public init(state: AppState, core: CoreActions, input: InputActions) {
        self.state = state
        self.core = core
        self.input = input
        self.panelController = PanelController(state: state, core: core)
        panelController.onOpenSettings = { [weak self] in self?.openSettings() }
    }

    public func start() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let img = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "PikoMacV")
            img?.isTemplate = true
            button.image = img
        }
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem("Geçmişi aç") { [weak self] in self?.showPanel(mode: .general) })
        menu.addItem(ClosureMenuItem("Sabitleri aç") { [weak self] in self?.showPanel(mode: .pinned) })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Ayarlar…") { [weak self] in self?.openSettings() })
        menu.addItem(ClosureMenuItem("Kurulum sihirbazı…") { [weak self] in self?.openOnboarding() })
        menu.addItem(ClosureMenuItem("Geçmişi temizle") { [weak self] in self?.confirmClear() })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("PikoMacV'den çık") { NSApp.terminate(nil) })
        item.menu = menu
        statusItem = item

        if !input.trackpadGestureAvailable,
           state.settings.bindings.contains(where: { $0.trigger == .trackpadThreeFingerDoubleTap }) {
            state.settings.bindings.removeAll { $0.trigger == .trackpadThreeFingerDoubleTap }
            input.apply(bindings: state.settings.bindings)
            core.settingsChanged()
        }
        if !state.settings.onboardingDone { openOnboarding() }
    }

    public func showPanel(mode: PanelMode) {
        if panelController.isVisible && panelController.mode == mode {
            panelController.close()
        } else {
            panelController.show(mode: mode)
        }
    }

    // MARK: Tanılama (yalnızca `--debug-hooks`)

    /// Pencere yakalamayı etkinleştirir (panel `sharingType = .readOnly`).
    public func debugEnable() { panelController.debugCapture = true; DebugFlags.syntheticGlass = true }

    /// Açık panelin görüntüsünü dosyaya yazar.
    public func debugSnapshot(to url: URL) { panelController.debugSnapshot(to: url) }

    public func debugClosePanel() { panelController.close() }
    public func debugSelectTab(_ name: String) { panelController.debugSelectTab(name) }
    public func debugSelectRow(_ index: Int) { panelController.debugSelectRow(index) }

    /// "light" / "dark" / "system".
    public func debugSetAppearance(_ name: String) {
        switch name {
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        default: NSApp.appearance = nil
        }
    }

    /// Ayarlar penceresini verilen sekmeyle (genel, kısayollar, depolama, gizlilik) yeniden açar.
    public func debugOpenSettings(tab: String) {
        let idx = ["genel": 0, "kısayollar": 1, "depolama": 2, "gizlilik": 3][tab.lowercased()] ?? 0
        panelController.close()
        settingsWindow?.close()
        settingsWindow = makeWindow(title: "PikoMacV Ayarları",
                                    content: NSHostingView(rootView: SettingsView(state: state, core: core, input: input, initialTab: idx)))
        present(settingsWindow!)
    }

    public func debugOpenOnboarding(step: Int) {
        panelController.close()
        // İlk kurulum görünümü: kayıtlı tetikleyici yok, önerilen kısayollar gerçekten boşta.
        state.settings.bindings = []
        input.apply(bindings: [])
        onboardingWindow?.close()
        let view = OnboardingView(state: state, core: core, input: input, initialStep: step) { [weak self] in
            self?.onboardingWindow?.close(); self?.onboardingWindow = nil
        }
        onboardingWindow = makeWindow(title: "PikoMacV Kurulumu", content: NSHostingView(rootView: view))
        present(onboardingWindow!)
    }

    /// "settings" / "onboarding" penceresinin görüntüsünü yazar.
    public func debugSnapshotWindow(_ which: String, to url: URL) {
        guard let w = which == "settings" ? settingsWindow : onboardingWindow else { return }
        let scale = w.backingScaleFactor
        let dark = DebugCapture.isDark(w)
        guard let image = DebugCapture.windowImage(w) ?? w.contentView.flatMap({ DebugCapture.viewImage($0) }) else { return }
        if let data = DebugCapture.compose(content: image, scale: scale, dark: dark, cornerRadius: 12) {
            try? data.write(to: url)
        }
    }

    // MARK: Pencereler

    private func makeWindow(title: String, content: NSView) -> NSWindow {
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: content.fittingSize),
                         styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        w.title = title
        w.contentView = content
        w.isReleasedWhenClosed = false
        w.center()
        return w
    }

    private func present(_ w: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    func openSettings() {
        panelController.close()
        if settingsWindow == nil {
            settingsWindow = makeWindow(title: "PikoMacV Ayarları",
                                        content: NSHostingView(rootView: SettingsView(state: state, core: core, input: input)))
        }
        present(settingsWindow!)
    }

    func openOnboarding() {
        panelController.close()
        onboardingWindow?.close()
        let view = OnboardingView(state: state, core: core, input: input) { [weak self] in
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
        }
        onboardingWindow = makeWindow(title: "PikoMacV Kurulumu", content: NSHostingView(rootView: view))
        present(onboardingWindow!)
    }

    private func confirmClear() {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "Geçmiş temizlensin mi?"
        a.informativeText = "Sabitler korunur. Bu işlem geri alınamaz."
        a.addButton(withTitle: "Temizle")
        a.addButton(withTitle: "Vazgeç")
        a.alertStyle = .warning
        if a.runModal() == .alertFirstButtonReturn { core.clearHistory() }
    }
}
