import AppKit
import ServiceManagement
import SwiftUI
import PikoMacVKit

struct SettingsView: View {
    @ObservedObject var state: AppState
    let core: CoreActions
    let input: InputActions
    @Local private var tab: Int

    init(state: AppState, core: CoreActions, input: InputActions, initialTab: Int = 0) {
        self.state = state; self.core = core; self.input = input
        _tab = Local(wrappedValue: initialTab)
    }

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettings(state: state, core: core)
                .tabItem { Label("Genel", systemImage: "gearshape") }.tag(0)
            ShortcutSettings(state: state, core: core, input: input)
                .tabItem { Label("Kısayollar", systemImage: "keyboard") }.tag(1)
            StorageSettings(state: state, core: core)
                .tabItem { Label("Depolama", systemImage: "internaldrive") }.tag(2)
            PrivacySettings(state: state, core: core)
                .tabItem { Label("Gizlilik", systemImage: "lock.shield") }.tag(3)
        }
        .frame(width: 520, height: 460)
    }
}

// MARK: Genel

struct GeneralSettings: View {
    @ObservedObject var state: AppState
    let core: CoreActions

    var body: some View {
        Form {
            Section {
                Stepper(value: Binding(get: { state.settings.historyLimit },
                                       set: { state.settings.historyLimit = min(1000, max(100, $0)); core.settingsChanged() }),
                        in: 100...1000, step: 50) {
                    Text("Geçmiş sınırı: \(state.settings.historyLimit) öğe")
                }
                Toggle("Oturum açılışında başlat", isOn: Binding(get: { state.settings.launchAtLogin }, set: setLaunch))
            }
            Section("Yok sayılan uygulamalar") {
                if state.settings.ignoredBundleIDs.isEmpty {
                    Text("Bu uygulamalardan kopyalananlar geçmişe alınmaz.").foregroundStyle(.secondary)
                }
                ForEach(state.settings.ignoredBundleIDs, id: \.self) { id in
                    HStack {
                        Text(appName(id))
                        Text(id).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button { remove(id) } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain)
                    }
                }
                Button("Uygulama ekle…") { chooseApp() }
            }
        }
        .formStyle(.grouped)
    }

    private func setLaunch(_ on: Bool) {
        state.settings.launchAtLogin = on
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("PikoMacV: oturum açılışı ayarlanamadı: \(error)")
        }
        core.settingsChanged()
    }

    private func appName(_ id: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return id
    }

    private func remove(_ id: String) {
        state.settings.ignoredBundleIDs.removeAll { $0 == id }
        core.settingsChanged()
    }

    private func chooseApp() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.application]
        p.directoryURL = URL(fileURLWithPath: "/Applications")
        p.allowsMultipleSelection = false
        p.prompt = "Seç"
        guard p.runModal() == .OK, let url = p.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
        if !state.settings.ignoredBundleIDs.contains(id) {
            state.settings.ignoredBundleIDs.append(id)
            core.settingsChanged()
        }
    }
}

// MARK: Kısayollar

struct ShortcutSettings: View {
    @ObservedObject var state: AppState
    let core: CoreActions
    let input: InputActions
    @Local private var failures: [UUID: String] = [:]
    @Local private var granted = false
    @StateObject private var trackpad = TrackpadTestState()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !granted {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text("Otomatik yapıştırma ve fare tuşu tetikleyicileri için Erişilebilirlik izni gerekir.")
                            .font(.callout)
                        Spacer()
                        Button("İzin ver") { input.requestAccessibility() }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.15)))
                }
                section("Geçmişi aç", .general)
                Divider()
                section("Sabitleri aç", .pinned)
            }
            .padding(20)
        }
        .onAppear { granted = input.accessibilityGranted }
        .onReceive(timer) { _ in granted = input.accessibilityGranted }
    }

    private func section(_ title: String, _ mode: PanelMode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            TriggerEditor(mode: mode,
                          bindings: Binding(get: { state.settings.bindings }, set: { state.settings.bindings = $0 }),
                          input: input, failures: failures, trackpad: trackpad, onChange: apply)
        }
    }

    private func apply() {
        failures = input.apply(bindings: state.settings.bindings)
        core.settingsChanged()
    }
}

// MARK: Depolama

struct StorageSettings: View {
    @ObservedObject var state: AppState
    let core: CoreActions
    @Local private var confirmClear = false

    private let gb: Int64 = 1024 * 1024 * 1024
    private let mb: Int64 = 1024 * 1024

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading) {
                    Text("Tek dosya kopyalama sınırı: \(state.settings.maxFileCopyBytes / mb) MB")
                    Slider(value: Binding(get: { Double(state.settings.maxFileCopyBytes / mb) },
                                          set: { state.settings.maxFileCopyBytes = Int64($0) * mb; core.settingsChanged() }),
                           in: 10...500, step: 10)
                }
                Stepper(value: Binding(get: { Int(state.settings.vaultCapBytes / gb) },
                                       set: { state.settings.vaultCapBytes = Int64($0) * gb; core.settingsChanged() }),
                        in: 1...20) {
                    Text("Toplam depo sınırı: \(state.settings.vaultCapBytes / gb) GB")
                }
            }
            Section("Kullanım") {
                let cap = max(state.settings.vaultCapBytes, 1)
                let f = min(1, Double(state.vaultUsedBytes) / Double(cap))
                ProgressView(value: f).tint(f > 0.85 ? .red : (f >= 0.6 ? .orange : .accentColor))
                Text(Fmt.storage(used: state.vaultUsedBytes, cap: state.settings.vaultCapBytes)).foregroundStyle(.secondary)
                Text("Sabitlenen dosyalar hiçbir zaman otomatik silinmez. Depo dolduğunda yalnızca sabitlenmemiş, en eski dosya kopyaları silinir.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button("Geçmişi temizle", role: .destructive) { confirmClear = true }
            }
        }
        .formStyle(.grouped)
        .alert("Geçmiş temizlensin mi?", isPresented: $confirmClear) {
            Button("Temizle", role: .destructive) { core.clearHistory() }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Sabitler korunur. Bu işlem geri alınamaz.")
        }
    }
}

// MARK: Gizlilik

struct PrivacySettings: View {
    @ObservedObject var state: AppState
    let core: CoreActions

    private let durations: [(String, Double)] = [("15 dk", 900), ("1 sa", 3600), ("2 sa", 7200), ("8 sa", 28800)]

    var body: some View {
        Form {
            Section {
                Picker("Gizli oturum süresi", selection: Binding(
                    get: { state.settings.secretSessionSeconds },
                    set: { state.settings.secretSessionSeconds = $0; core.settingsChanged() })) {
                    ForEach(durations, id: \.1) { Text($0.0).tag($0.1) }
                    if !durations.contains(where: { $0.1 == state.settings.secretSessionSeconds }) {
                        Text("\(Int(state.settings.secretSessionSeconds / 60)) dk").tag(state.settings.secretSessionSeconds)
                    }
                }
                Stepper(value: Binding(get: { Int(state.settings.secretClipboardClearSeconds) },
                                       set: { state.settings.secretClipboardClearSeconds = Double(min(120, max(10, $0))); core.settingsChanged() }),
                        in: 10...120, step: 5) {
                    Text("Gizli öğe panodan \(Int(state.settings.secretClipboardClearSeconds)) sn sonra silinir")
                }
            }
            Section("Bilgi") {
                Label("Gizli içerik Mac Anahtar Zinciri'nde saklanır.", systemImage: "key.fill")
                Label("PikoMacV, ekran paylaşımında ve kayıtlarda görünmez.", systemImage: "eye.slash")
                Label("Parola yöneticilerinden kopyalananlar hiçbir zaman kaydedilmez.", systemImage: "lock.shield")
            }
        }
        .formStyle(.grouped)
    }
}
