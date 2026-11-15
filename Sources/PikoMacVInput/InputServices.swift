import AppKit
import Carbon
import PikoMacVKit

/// Carbon olay geri çağrısı için paylaşılan kimlik → mod tablosu.
private final class HotKeyShared: @unchecked Sendable {
    private let lock = NSLock()
    private var map: [UInt32: PanelMode] = [:]
    var sink: (@Sendable (PanelMode) -> Void)?
    func set(_ m: [UInt32: PanelMode]) { lock.lock(); map = m; lock.unlock() }
    func mode(_ id: UInt32) -> PanelMode? { lock.lock(); defer { lock.unlock() }; return map[id] }
}

private let hotKeyShared = HotKeyShared()
private let signature: OSType = 0x50414E4F // 'PANO'

private let hotKeyHandler: EventHandlerUPP = { _, event, _ in
    var hkID = EventHotKeyID()
    let st = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                               nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
    if st == noErr, let mode = hotKeyShared.mode(hkID.id) { hotKeyShared.sink?(mode) }
    return noErr
}

@MainActor
public final class InputServices: InputActions {
    public var onTrigger: ((PanelMode) -> Void)?

    private var handlerRef: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var registeredCombos: Set<UInt64> = []
    private let mouse = MouseTap()
    private let multitouch = MultitouchMonitor()
    private var lastBindings: [Binding] = []
    private var suspended = false

    public init() {
        let fire: @Sendable (PanelMode) -> Void = { [weak self] mode in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.onTrigger?(mode) } }
        }
        hotKeyShared.sink = fire
        mouseShared.onFire = fire
    }

    // MARK: Kurulum

    @discardableResult
    public func apply(bindings: [Binding]) -> [UUID: String] {
        lastBindings = bindings
        return rebuild()
    }

    private func teardown() {
        for r in hotKeyRefs { UnregisterEventHotKey(r) }
        hotKeyRefs = []; registeredCombos = []
        hotKeyShared.set([:])
        mouse.stop()
        multitouch.stopMonitoring()
    }

    private func rebuild() -> [UUID: String] {
        teardown()
        guard !suspended else { return [:] }
        var failures: [UUID: String] = [:]

        if handlerRef == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 1, &spec, nil, &handlerRef)
        }

        var idMap: [UInt32: PanelMode] = [:]
        var nextID: UInt32 = 1
        var buttons: [Int: PanelMode] = [:]
        var mouseBindings: [Binding] = []
        var wantsTrackpad: [PanelMode] = []

        for b in lastBindings {
            switch b.trigger {
            case let .keyboard(code, mods):
                var ref: EventHotKeyRef?
                let id = nextID; nextID += 1
                let st = RegisterEventHotKey(code, mods, EventHotKeyID(signature: signature, id: id),
                                             GetApplicationEventTarget(), 0, &ref)
                if st == noErr, let ref {
                    hotKeyRefs.append(ref); idMap[id] = b.mode
                    registeredCombos.insert(Self.comboKey(code, mods))
                } else if st == OSStatus(eventHotKeyExistsErr) {
                    failures[b.id] = "Bu kısayol başka bir uygulama tarafından kullanılıyor"
                } else {
                    failures[b.id] = "Bu kısayol kaydedilemedi"
                }
            case let .mouseButton(n):
                if n < 2 { failures[b.id] = "Sol ve sağ tuş atanamaz" } else {
                    mouseBindings.append(b)
                    if buttons[n] == nil { buttons[n] = b.mode }
                }
            case .trackpadThreeFingerDoubleTap:
                wantsTrackpad.append(b.mode)
            }
        }
        hotKeyShared.set(idMap)

        if !mouseBindings.isEmpty {
            mouseShared.setButtons(buttons)
            if !mouse.start() {
                mouseShared.setButtons([:])
                for b in mouseBindings { failures[b.id] = "Erişilebilirlik izni gerekli" }
            }
        }

        if let mode = wantsTrackpad.first {
            let sink = hotKeyShared.sink
            let ok = multitouch.startMonitoring { sink?(mode) }
            if !ok {
                for b in lastBindings where b.trigger == .trackpadThreeFingerDoubleTap {
                    failures[b.id] = "Bu Mac'te dokunmatik yüzey hareketi kullanılamıyor"
                }
            }
        }
        return failures
    }

    private static func comboKey(_ code: UInt32, _ mods: UInt32) -> UInt64 { UInt64(code) << 32 | UInt64(mods) }

    public func setSuspended(_ suspended: Bool) {
        guard self.suspended != suspended else { return }
        self.suspended = suspended
        _ = rebuild()
    }

    // MARK: Çakışma ve öneri

    public func conflict(for trigger: Trigger) -> String? {
        switch trigger {
        case let .mouseButton(n): return n < 2 ? "Sol ve sağ tuş atanamaz" : nil
        case .trackpadThreeFingerDoubleTap: return nil
        case let .keyboard(code, mods):
            if let s = Conflicts.system(keyCode: code, modifiers: mods) { return s }
            if let s = Conflicts.common(keyCode: code, modifiers: mods) { return s }
            if registeredCombos.contains(Self.comboKey(code, mods)) { return nil }
            // Deneme kaydı
            var ref: EventHotKeyRef?
            let st = RegisterEventHotKey(code, mods, EventHotKeyID(signature: signature, id: 0xFFFF),
                                         GetApplicationEventTarget(), 0, &ref)
            if let ref { UnregisterEventHotKey(ref) }
            if st == OSStatus(eventHotKeyExistsErr) { return "Başka bir uygulama tarafından kullanılıyor" }
            return nil
        }
    }

    public func suggestions(count: Int) -> [Trigger] {
        let c = UInt32(cmdKey), o = UInt32(optionKey), ctl = UInt32(controlKey), s = UInt32(shiftKey)
        let V: UInt32 = 9, B: UInt32 = 11, C: UInt32 = 8, P: UInt32 = 35
        var cands: [Trigger] = [
            .keyboard(keyCode: V, modifiers: ctl | o | c), .keyboard(keyCode: B, modifiers: ctl | o | c),
            .keyboard(keyCode: V, modifiers: o), .keyboard(keyCode: V, modifiers: o | s),
            .keyboard(keyCode: V, modifiers: ctl | o), .keyboard(keyCode: B, modifiers: ctl | o),
            .keyboard(keyCode: V, modifiers: ctl | s), .keyboard(keyCode: B, modifiers: o | c),
            .keyboard(keyCode: C, modifiers: ctl | o | c), .keyboard(keyCode: P, modifiers: ctl | o | c),
        ]
        for f: UInt32 in [105, 107, 113, 106, 64, 79, 80] { cands.append(.keyboard(keyCode: f, modifiers: 0)) }
        var out: [Trigger] = []
        for t in cands where conflict(for: t) == nil {
            out.append(t)
            if out.count >= count { break }
        }
        return out
    }

    public func displayString(for trigger: Trigger) -> String {
        switch trigger {
        case let .keyboard(code, mods): return KeyNames.modifierGlyphs(mods) + KeyNames.name(for: code)
        case let .mouseButton(n): return n == 2 ? "Orta fare tuşu" : "Fare tuşu \(n + 1)"
        case .trackpadThreeFingerDoubleTap: return "Üç parmakla çift dokunma"
        }
    }

    // MARK: Fare tuşu yakalama

    public func captureNextMouseButton() async -> Int? {
        await withCheckedContinuation { (cont: CheckedContinuation<Int?, Never>) in
            var monitors: [Any] = []
            var finished = false
            func finish(_ value: Int?) {
                guard !finished else { return }
                finished = true
                for m in monitors { NSEvent.removeMonitor(m) }
                cont.resume(returning: value)
            }
            // Sınıf içi kapanışlar ana iş parçacığında çalışır.
            let handler: (NSEvent) -> Void = { e in
                let n = e.buttonNumber
                DispatchQueue.main.async { finish(n) }
            }
            if let g = NSEvent.addGlobalMonitorForEvents(matching: .otherMouseDown, handler: handler) { monitors.append(g) }
            if let l = NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown, handler: { e in handler(e); return nil }) { monitors.append(l) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { finish(nil) }
        }
    }

    // MARK: Erişilebilirlik ve izleme paneli

    public var accessibilityGranted: Bool { AXIsProcessTrusted() }

    public func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    public var trackpadGestureAvailable: Bool { multitouch.available }

    /// Hareketi gerçekten algılayabildiğimizi doğrular: kullanıcı süre içinde
    /// üç parmakla çift dokunursa true. Test bitince önceki tetikleyiciler geri kurulur.
    public func testTrackpadGesture(timeout: TimeInterval) async -> Bool {
        guard multitouch.available else { return false }
        teardown()
        let result: Bool = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            var finished = false
            let finish: (Bool) -> Void = { value in
                guard !finished else { return }
                finished = true
                cont.resume(returning: value)
            }
            let started = multitouch.startMonitoring {
                DispatchQueue.main.async { finish(true) }
            }
            if !started { finish(false); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { finish(false) }
        }
        // Tanılama: sonucu dosyaya yaz (Application Support/PikoMacV/trackpad-test.log).
        if let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("PikoMacV") {
            let text = "\(Date()) sonuc=\(result)\n\(multitouch.diagnostics)\n\n"
            let url = dir.appendingPathComponent("trackpad-test.log")
            if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(text.utf8)); try? h.close() }
            else { try? text.write(to: url, atomically: true, encoding: .utf8) }
        }
        _ = rebuild()
        return result
    }
}
