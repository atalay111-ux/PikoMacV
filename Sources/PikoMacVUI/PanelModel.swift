import AppKit
import Combine
import SwiftUI
import PikoMacVKit

enum PanelTab: CaseIterable, Hashable {
    case pinned, suitable, text, image, file, all
    var title: String {
        switch self {
        case .pinned: return "Sabitler"
        case .suitable: return "Uygun"
        case .text: return "Metin"
        case .image: return "Görsel"
        case .file: return "Dosya"
        case .all: return "Tümü"
        }
    }
}

enum PanelRow: Identifiable {
    case item(ClipItem)
    case pin(PinnedItem)
    case summary(Int)
    var id: String {
        switch self {
        case .item(let i): return i.id.uuidString
        case .pin(let p): return "pin-" + p.id.uuidString
        case .summary: return "summary"
        }
    }
}

enum PanelSheet {
    case pinItem(ClipItem, secret: Bool)
    case newPin
    case editPin(PinnedItem)
    case confirmDeletePin(PinnedItem)
    var id: String {
        switch self {
        case .pinItem(let i, _): return "pinItem-\(i.id)"
        case .newPin: return "newPin"
        case .editPin(let p): return "edit-\(p.id)"
        case .confirmDeletePin(let p): return "del-\(p.id)"
        }
    }
}

@MainActor
final class PanelModel: ObservableObject {
    let state: AppState
    let core: CoreActions
    let target: TargetApp?

    @Published var query = "" { didSet { if query != oldValue { selection = 0 } } }
    @Published var tab: PanelTab { didSet { if tab != oldValue { selection = 0 } } }
    @Published var selection = 0
    @Published var sheet: PanelSheet?
    @Published var revealed: [UUID: String] = [:]
    @Published var showAllPinned = false

    var authInProgress = false
    var onClose: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    var onRefocus: () -> Void = {}

    private var hideTasks: [UUID: Task<Void, Never>] = [:]
    private var cancellable: AnyCancellable?

    init(state: AppState, core: CoreActions, target: TargetApp?, mode: PanelMode) {
        self.state = state
        self.core = core
        self.target = target
        self.tab = mode == .pinned ? .pinned : .suitable
        cancellable = state.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.objectWillChange.send() }
        }
    }

    var isPinnedTab: Bool { tab == .pinned }

    // MARK: Satırlar

    private func matches(_ item: ClipItem, _ q: String) -> Bool {
        if q.isEmpty { return true }
        if let t = item.text, t.localizedCaseInsensitiveContains(q) { return true }
        if let a = item.sourceAppName, a.localizedCaseInsensitiveContains(q) { return true }
        return item.files.contains { $0.name.localizedCaseInsensitiveContains(q) }
    }

    func isSuitable(_ item: ClipItem) -> Bool { core.suitability(of: item, for: target) != nil }

    var rows: [PanelRow] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if tab == .pinned {
            let pins = state.pins.filter { p in
                q.isEmpty || p.label.localizedCaseInsensitiveContains(q) || (!p.isSecret && matches(p.item, q))
            }
            if showAllPinned { return pins.map { .pin($0) } }
            let ok = pins.filter { isSuitable($0.item) }
            let hidden = pins.count - ok.count
            return ok.map { .pin($0) } + (hidden > 0 ? [.summary(hidden)] : [])
        }
        let items = state.items.filter { matches($0, q) }
        switch tab {
        case .suitable:
            let ok = items.filter { isSuitable($0) }
            let hidden = items.count - ok.count
            return ok.map { .item($0) } + (hidden > 0 ? [.summary(hidden)] : [])
        case .text: return items.filter { $0.kind == .text || $0.kind == .link }.map { .item($0) }
        case .image: return items.filter { $0.kind == .image }.map { .item($0) }
        case .file: return items.filter { $0.kind == .file }.map { .item($0) }
        default: return items.map { .item($0) }
        }
    }

    func clampedSelection(_ count: Int) -> Int { count == 0 ? 0 : min(max(selection, 0), count - 1) }

    // MARK: Gezinme

    func move(_ delta: Int) {
        let n = rows.count
        guard n > 0 else { return }
        selection = ((clampedSelection(n) + delta) % n + n) % n
    }

    func cycleTab(_ delta: Int) {
        let all = PanelTab.allCases
        let i = all.firstIndex(of: tab) ?? 0
        tab = all[((i + delta) % all.count + all.count) % all.count]
    }

    // MARK: Eylemler

    func activate(index: Int, plain: Bool = false) {
        let rows = self.rows
        guard rows.indices.contains(index) else { return }
        switch rows[index] {
        case .summary:
            if isPinnedTab { showAllPinned = true } else { tab = .all }
            selection = 0
        case .item(let item):
            paste(item: item, plain: plain)
        case .pin(let pin):
            paste(pin: pin, plain: plain)
        }
    }

    func activateSelected(plain: Bool = false) {
        activate(index: clampedSelection(rows.count), plain: plain)
    }

    private func mode(for item: ClipItem, plain: Bool) -> PasteMode {
        if plain, item.kind == .text || item.kind == .link { return .plainText }
        return core.suitability(of: item, for: target)?.mode ?? .native
    }

    private func paste(item: ClipItem, plain: Bool) {
        if item.kind == .file && !core.isAvailable(item) { NSSound.beep(); return }
        let m = mode(for: item, plain: plain)
        onClose()
        core.paste(item, mode: m, into: target)
    }

    private func paste(pin: PinnedItem, plain: Bool) {
        if pin.item.kind == .file && !core.isAvailable(pin.item) { NSSound.beep(); return }
        let m = pin.isSecret ? PasteMode.native : mode(for: pin.item, plain: plain)
        onClose()
        core.paste(pin, mode: m, into: target)
    }

    func pasteNth(_ n: Int) {
        let rows = self.rows
        guard rows.indices.contains(n) else { return }
        if case .summary = rows[n] { return }
        activate(index: n)
    }

    func deleteSelected() {
        let rows = self.rows
        let i = clampedSelection(rows.count)
        guard rows.indices.contains(i) else { return }
        switch rows[i] {
        case .item(let item): core.delete(item)
        case .pin(let pin): sheet = .confirmDeletePin(pin)
        case .summary: break
        }
    }

    func beginPinSelected(secret: Bool) {
        guard !isPinnedTab else { return }
        let rows = self.rows
        let i = clampedSelection(rows.count)
        guard rows.indices.contains(i), case .item(let item) = rows[i] else { return }
        sheet = .pinItem(item, secret: secret && (item.kind == .text || item.kind == .link))
    }

    func beginEditSelected() {
        let rows = self.rows
        let i = clampedSelection(rows.count)
        guard isPinnedTab, rows.indices.contains(i), case .pin(let pin) = rows[i] else { return }
        sheet = .editPin(pin)
    }

    func closeSheet() { sheet = nil }

    // MARK: Gizli sabit gösterimi

    func toggleReveal(_ pin: PinnedItem) {
        if revealed[pin.id] != nil { hide(pin.id); return }
        authInProgress = true
        Task { @MainActor in
            let text = await core.revealSecret(pin)
            authInProgress = false
            onRefocus()
            guard let text else { return }
            withAnimation(.easeInOut(duration: 0.45)) { revealed[pin.id] = text }
            hideTasks[pin.id]?.cancel()
            hideTasks[pin.id] = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if !Task.isCancelled { self?.hide(pin.id) }
            }
        }
    }

    func hide(_ id: UUID) {
        hideTasks[id]?.cancel()
        hideTasks[id] = nil
        withAnimation(.easeInOut(duration: 0.3)) { _ = revealed.removeValue(forKey: id) }
    }

    func wipe() {
        hideTasks.values.forEach { $0.cancel() }
        hideTasks = [:]
        revealed = [:]
    }
}
