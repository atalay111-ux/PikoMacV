import AppKit
import SwiftUI
import PikoMacVKit

@MainActor
final class OnboardingModel: ObservableObject {
    @Published var step = 0
    @Published var draft: [PikoMacVBinding]
    @Published var granted = false
    let trackpad = TrackpadTestState()
    var suggestions: [Trigger] = []
    private var seeded = false

    init(state: AppState, input: InputActions, step: Int = 0) {
        self.step = step
        draft = state.settings.bindings
        suggestions = input.suggestions(count: 4)
        granted = input.accessibilityGranted
    }

    func seedDefaults() {
        guard !seeded else { return }
        seeded = true
        if draft.contains(where: { $0.mode == .general }) || draft.contains(where: { $0.mode == .pinned }) { return }
        if suggestions.indices.contains(0) { draft.append(PikoMacVBinding(mode: .general, trigger: suggestions[0])) }
        if suggestions.indices.contains(1) { draft.append(PikoMacVBinding(mode: .pinned, trigger: suggestions[1])) }
    }
}

struct OnboardingView: View {
    @ObservedObject var state: AppState
    let core: CoreActions
    let input: InputActions
    let onFinish: () -> Void
    @StateObject private var model: OnboardingModel
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(state: AppState, core: CoreActions, input: InputActions, initialStep: Int = 0, onFinish: @escaping () -> Void) {
        self.state = state; self.core = core; self.input = input; self.onFinish = onFinish
        let m = OnboardingModel(state: state, input: input, step: initialStep)
        if initialStep >= 2 { m.seedDefaults() }
        _model = StateObject(wrappedValue: m)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule().fill(i <= model.step ? Color.accentColor : Color.primary.opacity(0.15)).frame(height: 4)
                }
            }
            .padding(.horizontal, 24).padding(.top, 20)
            Group {
                switch model.step {
                case 0: welcome
                case 1: permission
                case 2: shortcuts
                default: done
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(24)
            Divider()
            HStack {
                Button("Geri") { model.step -= 1 }.disabled(model.step == 0).opacity(model.step == 0 ? 0 : 1)
                Spacer()
                if model.step == 1 && !model.granted { Button("Atla") { model.step += 1 } }
                if model.step < 3 {
                    Button("İleri") { model.step += 1 }.keyboardShortcut(.defaultAction)
                } else {
                    Button("Başla") { finish() }.keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
        }
        .frame(width: 560, height: 640)
        .onReceive(timer) { _ in model.granted = input.accessibilityGranted }
        .onChange(of: model.step) { _, s in if s == 2 { model.seedDefaults() } }
    }

    // MARK: Adımlar

    private func heading(_ icon: String, _ title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 28)).foregroundStyle(Color.accentColor)
            Text(title).font(.system(size: 24, weight: .bold))
        }
        .padding(.bottom, 12)
    }

    private func bullet(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).frame(width: 24).foregroundStyle(Color.accentColor)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("clipboard", "PikoMacV'ye hoş geldiniz")
            bullet("clock.arrow.circlepath", "Kopyaladığınız metin, görsel ve dosyalar geçmişte saklanır.")
            bullet("cursorarrow.rays", "Kısayolla fare imlecinizin olduğu yerde açılır; seçtiğiniz öğe doğrudan yapıştırılır.")
            bullet("pin.fill", "Sık kullandıklarınızı sabitleyin; parola gibi gizli içerikleri Anahtar Zinciri'nde güvenle saklayın.")
        }
    }

    private var permission: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("hand.raised.fill", "Erişilebilirlik izni")
            Text("PikoMacV'nin seçtiğiniz öğeyi otomatik yapıştırabilmesi ve fare tuşu tetikleyicilerinin çalışması için Erişilebilirlik izni gerekir. İzin vermezseniz öğe panoya kopyalanır, yapıştırmayı siz yaparsınız.")
                .fixedSize(horizontal: false, vertical: true)
            Button("Erişilebilirlik iznini ver") { input.requestAccessibility() }
            HStack(spacing: 8) {
                Image(systemName: model.granted ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(model.granted ? Color.green : Color.secondary)
                Text(model.granted ? "İzin verildi" : "İzin bekleniyor…")
            }
            Text("Bu adımı şimdilik atlayabilirsiniz.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var shortcuts: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                heading("keyboard", "Kısayollar")
                Text("Fare tuşuna atayacaksanız zor bir kombinasyon seçin; farenizin yazılımında bu kısayolu tuşa bağlayın ya da doğrudan 'Fare tuşu ekle'yi kullanın.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("Geçmiş").font(.headline)
                TriggerEditor(mode: .general, bindings: $model.draft, input: input, suggestions: model.suggestions, trackpad: model.trackpad)
                Divider()
                Text("Sabitler").font(.headline)
                TriggerEditor(mode: .pinned, bindings: $model.draft, input: input, suggestions: model.suggestions, trackpad: model.trackpad)
            }
        }
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("checkmark.seal.fill", "Hazırsınız")
            summary("Geçmişi aç", .general)
            summary("Sabitleri aç", .pinned)
            Text("Ayarları istediğiniz zaman menü çubuğundaki simgeden değiştirebilirsiniz.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private func summary(_ title: String, _ mode: PanelMode) -> some View {
        let list = model.draft.filter { $0.mode == mode }.map { input.displayString(for: $0.trigger) }
        return HStack(alignment: .top) {
            Text(title).fontWeight(.semibold).frame(width: 120, alignment: .leading)
            Text(list.isEmpty ? "Tetikleyici yok (menüden açabilirsiniz)" : list.joined(separator: "   "))
                .foregroundStyle(list.isEmpty ? .secondary : .primary)
        }
    }

    private func finish() {
        state.settings.bindings = model.draft
        state.settings.onboardingDone = true
        input.apply(bindings: model.draft)
        core.settingsChanged()
        onFinish()
    }
}
