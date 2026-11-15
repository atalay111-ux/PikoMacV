import AppKit
import PikoMacVCore
import PikoMacVInput
import PikoMacVKit
import PikoMacVUI

/// Kancalar için sahte hedef uygulama kategorileri (Core'daki tablo dahili olduğundan burada özet).
enum DebugTargets {
    static func category(_ bundleID: String) -> AppCategory {
        switch bundleID {
        case "com.apple.finder": return .fileManager
        case "com.apple.Terminal": return .terminal
        case "com.microsoft.Word": return .document
        case "com.apple.mail": return .messaging
        default: return .other
        }
    }
}

/// Tanılama: `PIKOMACV_FAKE_ACCESSIBILITY=1` ile ayarlardaki "Erişilebilirlik izni gerekir" uyarısı gizlenir
/// (izin verilmiş bir kurulumun görünümü). Yalnızca arayüze verilen sarmalayıcıda; gerçek davranışa dokunmaz.
@MainActor
final class DemoInput: InputActions {
    let base: InputActions
    init(_ base: InputActions) { self.base = base }
    var onTrigger: ((PanelMode) -> Void)? { get { base.onTrigger } set { base.onTrigger = newValue } }
    func apply(bindings: [Binding]) -> [UUID: String] { base.apply(bindings: bindings) }
    func suggestions(count: Int) -> [Trigger] { base.suggestions(count: count) }
    func conflict(for trigger: Trigger) -> String? { base.conflict(for: trigger) }
    func displayString(for trigger: Trigger) -> String { base.displayString(for: trigger) }
    func setSuspended(_ suspended: Bool) { base.setSuspended(suspended) }
    func captureNextMouseButton() async -> Int? { await base.captureNextMouseButton() }
    var accessibilityGranted: Bool { true }
    func requestAccessibility() {}
    var trackpadGestureAvailable: Bool { base.trackpadGestureAvailable }
    func testTrackpadGesture(timeout: TimeInterval) async -> Bool { await base.testTrackpadGesture(timeout: timeout) }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state = AppState()
    private var core: CoreServices!
    private var input: InputServices!
    private var ui: UIController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        core = CoreServices(state: state)
        core.start()
        if CommandLine.arguments.contains("--seed-demo") { core.seedDemo() }

        input = InputServices()
        let fakeAX = CommandLine.arguments.contains("--debug-hooks")
            && ProcessInfo.processInfo.environment["PIKOMACV_FAKE_ACCESSIBILITY"] == "1"
        ui = UIController(state: state, core: core, input: fakeAX ? DemoInput(input) : input)
        input.onTrigger = { [weak self] mode in self?.ui.showPanel(mode: mode) }
        input.apply(bindings: state.settings.bindings)

        ui.start()

        // Tanılama: `--debug-hooks` ile başlatılınca dışarıdan panel açılabilir.
        if CommandLine.arguments.contains("--debug-hooks") {
            ui.debugEnable()
            func hook(_ name: String, _ body: @escaping @MainActor (AppDelegate, String) -> Void) {
                DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.pikomacv.app.debug." + name), object: nil, queue: .main) { [weak self] note in
                    let arg = (note.object as? String) ?? ""
                    MainActor.assumeIsolated { if let self { body(self, arg) } }
                }
            }
            // Ekran görüntüsü kancaları (bkz. scripts/make-screenshots.sh).
            hook("appearance") { d, a in d.ui.debugSetAppearance(a) }                       // light | dark
            hook("tab") { d, a in d.ui.debugSelectTab(a) }                                   // Uygun, Sabitler, ...
            hook("select") { d, a in d.ui.debugSelectRow(Int(a) ?? 0) }                      // satır indeksi
            hook("settings") { d, a in d.ui.debugOpenSettings(tab: a) }                      // genel | kısayollar | depolama | gizlilik
            hook("onboarding") { d, a in d.ui.debugOpenOnboarding(step: Int(a) ?? 0) }       // adım indeksi
            hook("target") { d, a in                                                         // "bundleid|Ad" ya da boş (kaldır)
                let p = a.components(separatedBy: "|")
                guard p.count == 2 else { d.core.debugTargetOverride = nil; return }
                d.core.debugTargetOverride = TargetApp(bundleID: p[0], name: p[1], category: DebugTargets.category(p[0]), pid: 0)
            }
            hook("snapwindow") { d, a in                                                     // "settings|/yol.png" ya da "onboarding|/yol.png"
                let p = a.components(separatedBy: "|")
                guard p.count == 2 else { return }
                d.ui.debugSnapshotWindow(p[0], to: URL(fileURLWithPath: p[1]))
            }
            hook("close") { d, _ in d.ui.debugClosePanel() }
            hook("quit") { _, _ in NSApp.terminate(nil) }
            DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.pikomacv.app.debug.show"), object: nil, queue: .main) { [weak self] note in
                let pinned = (note.object as? String) == "pinned"
                MainActor.assumeIsolated { self?.ui.showPanel(mode: pinned ? .pinned : .general) }
            }
            // "etiket|metin|gizli(0/1)" ile sabit ekler.
            DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.pikomacv.app.debug.addpin"), object: nil, queue: .main) { [weak self] note in
                guard let parts = (note.object as? String)?.components(separatedBy: "|"), parts.count == 3 else { return }
                MainActor.assumeIsolated { self?.core.addPin(label: parts[0], text: parts[1], secret: parts[2] == "1") }
            }
            // "h<N>" geçmişteki, "p<N>" sabitlerdeki N. öğeyi panoya yazar (tuş göndermeden).
            DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.pikomacv.app.debug.paste"), object: nil, queue: .main) { [weak self] note in
                guard let s = note.object as? String, let n = Int(s.dropFirst()) else { return }
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if s.hasPrefix("h"), self.state.items.indices.contains(n) { self.core.paste(self.state.items[n], mode: .native, into: nil) }
                    if s.hasPrefix("p"), self.state.pins.indices.contains(n) { self.core.paste(self.state.pins[n], mode: .native, into: nil) }
                }
            }
            DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.pikomacv.app.debug.snap"), object: nil, queue: .main) { [weak self] note in
                guard let path = note.object as? String else { return }
                MainActor.assumeIsolated { self?.ui.debugSnapshot(to: URL(fileURLWithPath: path)) }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

// Aynı anda tek kopya çalışsın.
if let bundleID = Bundle.main.bundleIdentifier,
   NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).count > 1 {
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
