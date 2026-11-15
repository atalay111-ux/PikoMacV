import AppKit
import SwiftUI
import PikoMacVKit

final class PikoMacVPanel: NSPanel {
    var onResignKey: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}

@MainActor
final class PanelController {
    private let state: AppState
    private let core: CoreActions
    private var panel: PikoMacVPanel?
    private var hosting: NSHostingView<PanelView>?
    private var model: PanelModel?
    private var keyMonitor: Any?
    private var mouseMonitor: Any?
    private var sizeObserver: Any?
    private(set) var mode: PanelMode = .general
    var onOpenSettings: () -> Void = {}
    /// `--debug-hooks`: yakalama için pencere paylaşımını açar.
    var debugCapture = false

    init(state: AppState, core: CoreActions) {
        self.state = state
        self.core = core
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(mode: PanelMode) {
        if isVisible { close() }
        self.mode = mode
        let target = core.currentTarget()
        let model = PanelModel(state: state, core: core, target: target, mode: mode)
        model.onClose = { [weak self] in self?.close() }
        model.onOpenSettings = { [weak self] in self?.close(); self?.onOpenSettings() }
        model.onRefocus = { [weak self] in self?.panel?.makeKey() }
        self.model = model

        let panel = self.panel ?? makePanel()
        self.panel = panel
        let host = NSHostingView(rootView: PanelView(model: model, state: state))
        hosting = host
        panel.contentView = host
        let size = host.fittingSize
        panel.setContentSize(size)
        panel.setFrameOrigin(origin(for: size))
        if debugCapture { panel.sharingType = .readOnly }
        panel.makeKeyAndOrderFront(nil)
        installMonitors()
        observeSize(model)
    }

    func close() {
        removeMonitors()
        sizeObserver = nil
        model?.wipe()
        model = nil
        panel?.orderOut(nil)
        panel?.contentView = nil
        hosting = nil
    }

    private func makePanel() -> PikoMacVPanel {
        let p = PikoMacVPanel(contentRect: NSRect(x: 0, y: 0, width: PanelMetrics.width, height: 300),
                          styleMask: [.borderless, .nonactivatingPanel],
                          backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .floating
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.sharingType = .none
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.isReleasedWhenClosed = false
        p.onResignKey = { [weak self] in
            DispatchQueue.main.async {
                // Kip değiştirirken panel yeniden açılmış olabilir; yalnızca gerçekten odak kaybedildiyse kapat.
                guard let self, let m = self.model, !m.authInProgress, self.panel?.isKeyWindow != true else { return }
                self.close()
            }
        }
        return p
    }

    /// Tanılama (`--debug-hooks`): panel penceresini kendi gerçek görünümüyle yakalar ve sentetik masaüstü
    /// arka planı üstüne yerleştirir. Pencere yakalanamazsa katman çizimine düşer (cam arka plan olmadan).
    func debugSnapshot(to url: URL) {
        guard let panel, let view = panel.contentView else { return }
        let scale = panel.backingScaleFactor
        let dark = DebugCapture.isDark(panel)
        guard let image = DebugCapture.windowImage(panel) ?? DebugCapture.viewImage(view) else { return }
        if let data = DebugCapture.compose(content: image, scale: scale, dark: dark, cornerRadius: 18) {
            try? data.write(to: url)
        }
    }

    var debugWindow: NSWindow? { panel }

    func debugSelectTab(_ name: String) {
        guard let m = model else { return }
        m.query = ""
        if let t = PanelTab.allCases.first(where: { $0.title.lowercased() == name.lowercased() }) { m.tab = t }
    }

    func debugSelectRow(_ i: Int) { model?.selection = i }

    /// Tanılama: panelin pencere ayarı (yakalama için salt okunur paylaşım).
    func debugEnableCapture() { panel?.sharingType = .readOnly }

    // MARK: Konum ve boyut

    private func origin(for size: NSSize) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        var o = NSPoint(x: mouse.x, y: mouse.y - size.height)
        if let vf = screen?.visibleFrame {
            o.x = min(max(o.x, vf.minX), vf.maxX - size.width)
            o.y = min(max(o.y, vf.minY), vf.maxY - size.height)
        }
        return o
    }

    private func observeSize(_ model: PanelModel) {
        sizeObserver = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.resizeToFit() }
        }
    }

    private func resizeToFit() {
        guard let panel, let host = hosting, panel.isVisible else { return }
        let size = host.fittingSize
        guard abs(size.height - panel.frame.height) > 0.5 || abs(size.width - panel.frame.width) > 0.5 else { return }
        var f = panel.frame
        let top = f.maxY
        f.size = size
        f.origin.y = top - size.height
        if let vf = (panel.screen ?? NSScreen.main)?.visibleFrame, f.minY < vf.minY { f.origin.y = vf.minY }
        panel.setFrame(f, display: true)
    }

    // MARK: Olay izleme

    private func installMonitors() {
        removeMonitors()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            MainActor.assumeIsolated { self?.handleKey(e) ?? e }
        }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, let m = self.model, !m.authInProgress else { return }
                self.close()
            }
        }
    }

    private func removeMonitors() {
        if let k = keyMonitor { NSEvent.removeMonitor(k); keyMonitor = nil }
        if let m = mouseMonitor { NSEvent.removeMonitor(m); mouseMonitor = nil }
    }

    private static let digitKeyCodes: [UInt16: Int] = [18: 0, 19: 1, 20: 2, 21: 3, 23: 4, 22: 5, 26: 6, 28: 7, 25: 8]

    private func handleKey(_ e: NSEvent) -> NSEvent? {
        guard let model, let panel, e.window === panel else { return e }
        if debugCapture { return nil }   // demo: gerçek klavye girdisi arama alanına sızmasın
        let flags = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let cmd = flags.contains(.command), opt = flags.contains(.option), shift = flags.contains(.shift)
        let ctrl = flags.contains(.control)

        if e.keyCode == 53 { // Esc
            if model.sheet != nil { model.closeSheet() } else { close() }
            return nil
        }
        if let sheet = model.sheet {
            if case .confirmDeletePin = sheet { return e } // Return düğmeyi tetikler
            return e
        }
        if ctrl { return e }

        switch e.keyCode {
        case 126: model.move(-1); return nil
        case 125: model.move(1); return nil
        case 36, 76:
            model.activateSelected(plain: shift)
            return nil
        case 48:
            let rows = model.rows
            let sel = model.clampedSelection(rows.count)
            if !shift, rows.indices.contains(sel), case .summary = rows[sel] {
                model.activate(index: sel)
            } else {
                model.cycleTab(shift ? -1 : 1)
            }
            return nil
        case 123 where cmd: model.cycleTab(-1); return nil
        case 124 where cmd: model.cycleTab(1); return nil
        case 51 where cmd: model.deleteSelected(); return nil
        default: break
        }

        if let n = Self.digitKeyCodes[e.keyCode] {
            if cmd && !opt && !model.isPinnedTab { model.pasteNth(n); return nil }
            if opt && !cmd && model.isPinnedTab { model.pasteNth(n); return nil }
            return e
        }
        if cmd, let ch = e.charactersIgnoringModifiers?.lowercased() {
            switch ch {
            case "p": model.beginPinSelected(secret: shift); return nil
            case "n": model.sheet = .newPin; return nil
            case "e": model.beginEditSelected(); return nil
            case ",": model.onOpenSettings(); return nil
            default: break
            }
        }
        return e
    }
}
