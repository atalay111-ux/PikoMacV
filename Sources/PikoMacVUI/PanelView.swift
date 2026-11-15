import AppKit
import SwiftUI
import PikoMacVKit

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .popover
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

/// Tanılama (`--debug-hooks`): gerçek cam, pencere dışarıdan yakalanınca arkasında bir şey olmadığı için koyu gri
/// çıkar. Belge görüntülerinde yerine, camın yaklaşık görünümü olan yarı saydam dolgu çizilir.
enum DebugFlags {
    nonisolated(unsafe) static var syntheticGlass = false
}

struct SyntheticGlass: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        content
            .background(shape.fill(scheme == .dark ? Color(red: 0.118, green: 0.118, blue: 0.118).opacity(0.78) : Color.white.opacity(0.78)))
            .overlay(shape.strokeBorder(scheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.10), lineWidth: 1))
            .clipShape(shape)
    }
}

struct PanelBackground: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if DebugFlags.syntheticGlass {
            content.modifier(SyntheticGlass())
        } else if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: 18))
        } else {
            content
                .background(VisualEffectBackground())
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

enum PanelMetrics {
    static let width: CGFloat = 380
    static let rowHeight: CGFloat = 44
    static let rowSpacing: CGFloat = 2
    static let maxListHeight: CGFloat = 330
    static let sheetHeight: CGFloat = 250
}

struct PanelView: View {
    @ObservedObject var model: PanelModel
    @ObservedObject var state: AppState
    @FocusState private var searchFocused: Bool

    var body: some View {
        let rows = model.rows
        VStack(spacing: 8) {
            header
            ChipsRow(model: model)
            if let sheet = model.sheet {
                PanelSheetView(model: model, sheet: sheet)
                    .frame(height: PanelMetrics.sheetHeight)
            } else {
                list(rows)
            }
            PanelFooter(model: model, state: state)
        }
        .padding(12)
        .frame(width: PanelMetrics.width)
        .modifier(PanelBackground())
        .onAppear { focusSearch() }
        .onChange(of: model.sheet?.id) { _, new in if new == nil { focusSearch() } }
    }

    private func focusSearch() {
        DispatchQueue.main.async { searchFocused = !DebugFlags.syntheticGlass }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(model.isPinnedTab ? "Sabitlerde ara" : "Geçmişte ara", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($searchFocused)
                .allowsHitTesting(!DebugFlags.syntheticGlass)   // demo: gerçek klavye girdisi sızmasın
            if let t = model.target {
                Text("\(t.name) için")
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                    .frame(maxWidth: 140)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    @ViewBuilder
    private func list(_ rows: [PanelRow]) -> some View {
        if rows.isEmpty {
            Text(model.query.isEmpty ? (model.isPinnedTab ? "Henüz sabit yok" : "Burada henüz bir şey yok") : "Sonuç bulunamadı")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 70)
        } else {
            let sel = model.clampedSelection(rows.count)
            let h = min(CGFloat(rows.count) * (PanelMetrics.rowHeight + PanelMetrics.rowSpacing), PanelMetrics.maxListHeight)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: PanelMetrics.rowSpacing) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                            ClipRowView(model: model, row: row, index: idx, selected: idx == sel)
                                .id(row.id)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .onChange(of: model.selection) { _, _ in
                    let r = model.rows
                    let s = model.clampedSelection(r.count)
                    if r.indices.contains(s) { proxy.scrollTo(r[s].id) }
                }
            }
            .frame(height: h)
        }
    }
}

struct ChipsRow: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(PanelTab.allCases, id: \.self) { tab in
                    let on = model.tab == tab
                    Button { model.tab = tab } label: {
                        HStack(spacing: 3) {
                            if tab == .pinned { Image(systemName: "pin.fill").font(.system(size: 10)) }
                            Text(tab.title).font(.system(size: 12, weight: on ? .semibold : .regular))
                                .lineLimit(1).fixedSize()
                        }
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .foregroundStyle(on ? Color.white : Color.primary)
                        .background(Capsule().fill(on ? Color.accentColor : Color.primary.opacity(0.08)))
                        .fixedSize()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct PanelFooter: View {
    @ObservedObject var model: PanelModel
    @ObservedObject var state: AppState

    private var usageColor: Color {
        let cap = max(state.settings.vaultCapBytes, 1)
        let f = Double(state.vaultUsedBytes) / Double(cap)
        if f > 0.85 { return .red }
        if f >= 0.6 { return .orange }
        return .secondary
    }

    var body: some View {
        let cap = max(state.settings.vaultCapBytes, 1)
        let frac = min(1, max(0, Double(state.vaultUsedBytes) / Double(cap)))
        VStack(spacing: 5) {
            HStack {
                Text(model.isPinnedTab ? "↩ yapıştır · ⌘N yeni sabit · ⌘E düzenle" : "↩ yapıştır · ⌘P sabitle · ⇧↩ düz metin")
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(model.isPinnedTab ? "\(state.pins.count) sabit" : "\(state.items.count) / \(state.settings.historyLimit)")
                    .lineLimit(1).fixedSize()
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Image(systemName: "internaldrive").font(.system(size: 10)).foregroundStyle(.secondary)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.1))
                        Capsule().fill(usageColor).frame(width: max(4, g.size.width * frac))
                    }
                }
                .frame(height: 4)
                Text(Fmt.storage(used: state.vaultUsedBytes, cap: state.settings.vaultCapBytes))
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).fixedSize()
            }
        }
        .padding(.horizontal, 4)
    }
}
