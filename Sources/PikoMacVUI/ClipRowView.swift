import AppKit
import SwiftUI
import PikoMacVKit

struct ClipRowView: View {
    @ObservedObject var model: PanelModel
    let row: PanelRow
    let index: Int
    let selected: Bool
    @Local private var hover = false

    var body: some View {
        let info = RowInfo(model: model, row: row)
        HStack(spacing: 10) {
            IconTile(info: info, selected: selected)
            VStack(alignment: .leading, spacing: 2) {
                Text(info.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1).truncationMode(.tail)
                    .foregroundStyle(selected ? Color.white : Color.primary)
                subtitle(info)
            }
            Spacer(minLength: 4)
            if info.isSecretPin, case .pin(let pin) = row {
                Button { model.toggleReveal(pin) } label: {
                    Image(systemName: info.revealed != nil ? "eye.slash" : "eye")
                        .font(.system(size: 12))
                        .foregroundStyle(selected ? Color.white : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(info.revealed != nil ? "Gizle" : "Göster")
            }
            if hover || selected, let actions = rowActions {
                HStack(spacing: 2) {
                    iconButton(actions.pinSymbol, help: actions.pinHelp, action: actions.pin)
                    iconButton("trash", help: "Sil", action: actions.delete)
                }
            }
            if let hint = shortcutHint {
                Text(hint).font(.system(size: 11)).foregroundStyle(selected ? Color.white.opacity(0.8) : Color.secondary)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: PanelMetrics.rowHeight)
        .background(background(info))
        .opacity(info.unavailable ? 0.45 : 1)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture {
            model.selection = index
            model.activate(index: index)
        }
    }

    private struct RowActions {
        var pinSymbol: String
        var pinHelp: String
        var pin: () -> Void
        var delete: () -> Void
    }

    private var rowActions: RowActions? {
        switch row {
        case .summary: return nil
        case .item(let item):
            return RowActions(pinSymbol: "pin", pinHelp: "Sabitle",
                              pin: { model.selection = index; model.sheet = .pinItem(item, secret: false) },
                              delete: { model.core.delete(item) })
        case .pin(let pin):
            return RowActions(pinSymbol: "pin.slash", pinHelp: "Sabitten çıkar",
                              pin: { model.selection = index; model.sheet = .confirmDeletePin(pin) },
                              delete: { model.selection = index; model.sheet = .confirmDeletePin(pin) })
        }
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(selected ? Color.white.opacity(0.85) : Color.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var shortcutHint: String? {
        if case .summary = row { return nil }
        guard index < 9 else { return nil }
        return (model.isPinnedTab ? "⌥" : "⌘") + "\(index + 1)"
    }

    private func background(_ info: RowInfo) -> some View {
        ZStack {
            if selected {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.accentColor)
            } else {
                if info.risk > 0 {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.red.opacity(0.42 * info.risk))
                }
                if hover {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.08))
                }
            }
        }
    }

    @ViewBuilder
    private func subtitle(_ info: RowInfo) -> some View {
        let color: Color = selected ? .white.opacity(0.85) : .secondary
        if info.isSecretPin {
            HStack(spacing: 4) {
                SecretText(revealed: info.revealed)
                    .foregroundStyle(color)
                Text("· gizli").foregroundStyle(color)
            }
            .font(.system(size: 11)).lineLimit(1)
        } else {
            Text(info.subtitle)
                .font(.system(size: 11)).lineLimit(1).truncationMode(.tail)
                .foregroundStyle(color)
        }
    }
}

struct SecretText: View {
    let revealed: String?
    private static let fake = "Xmqwo Rtkpa Znd"
    @Local private var blur: CGFloat = 5

    var body: some View {
        Group {
            if let revealed {
                Text(Fmt.collapse(revealed, limit: 60))
                    .lineLimit(1)
                    .blur(radius: blur)
                    .onAppear {
                        blur = 5
                        withAnimation(.easeInOut(duration: 0.45)) { blur = 0 }
                    }
            } else {
                Text(Self.fake).blur(radius: 5).opacity(0.75)
            }
        }
        .id(revealed != nil)
    }
}

struct IconTile: View {
    let info: RowInfo
    let selected: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(selected ? Color.white.opacity(0.22) : Color.primary.opacity(0.09))
            if let img = info.thumbnail {
                Image(nsImage: img).resizable().scaledToFill()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            } else {
                Image(systemName: info.symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(selected ? Color.white : Color.secondary)
            }
        }
        .frame(width: 28, height: 28)
    }
}

/// Bir satırın gösterim verisi.
struct RowInfo {
    var title = ""
    var subtitle = ""
    var symbol = "textformat"
    var thumbnail: NSImage?
    var isSecretPin = false
    var revealed: String?
    var unavailable = false
    var risk: Double = 0

    @MainActor
    init(model: PanelModel, row: PanelRow) {
        let core = model.core
        switch row {
        case .summary(let n):
            title = "Buraya uygun olmayan \(n) öğe"
            subtitle = model.isPinnedTab ? "Tümünü göster" : "Tümünü göster"
            symbol = "tray.full"
        case .item(let item):
            title = Fmt.title(of: item)
            symbol = Fmt.symbol(of: item.kind)
            if item.kind == .image || item.kind == .file { thumbnail = core.thumbnail(for: item) }
            unavailable = item.kind == .file && !core.isAvailable(item)
            risk = max(0, min(1, core.evictionRisk(of: item)))
            var parts: [String] = []
            if let a = item.sourceAppName { parts.append(a) }
            parts.append(Fmt.relative(item.createdAt))
            parts += Self.extra(item, core: core, target: model.target, unavailable: unavailable)
            if risk > 0.85 { parts.append("sırada silinecek") }
            subtitle = parts.joined(separator: " · ")
        case .pin(let pin):
            title = pin.label
            isSecretPin = pin.isSecret
            revealed = model.revealed[pin.id]
            symbol = pin.isSecret ? "lock.fill" : "pin.fill"
            if !pin.isSecret && (pin.item.kind == .image || pin.item.kind == .file) { thumbnail = core.thumbnail(for: pin.item) }
            unavailable = pin.item.kind == .file && !core.isAvailable(pin.item)
            var parts: [String] = [pin.isSecret ? "" : Fmt.title(of: pin.item)]
            parts += Self.extra(pin.item, core: core, target: model.target, unavailable: unavailable, withTime: false)
            subtitle = parts.filter { !$0.isEmpty }.joined(separator: " · ")
        }
    }

    @MainActor
    private static func extra(_ item: ClipItem, core: CoreActions, target: TargetApp?, unavailable: Bool, withTime: Bool = true) -> [String] {
        var parts: [String] = []
        if item.kind == .file {
            let total = item.files.reduce(Int64(0)) { $0 + $1.byteSize }
            if total > 0 { parts.append(Fmt.bytes(total)) }
        }
        if unavailable { parts.append("dosya bulunamadı") }
        if let hint = core.suitability(of: item, for: target)?.hint { parts.append(hint) }
        return parts
    }
}
