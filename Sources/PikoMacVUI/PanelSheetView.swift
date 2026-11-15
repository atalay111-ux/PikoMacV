import SwiftUI
import PikoMacVKit

struct PanelSheetView: View {
    @ObservedObject var model: PanelModel
    let sheet: PanelSheet

    var body: some View {
        Group {
            switch sheet {
            case .confirmDeletePin(let pin):
                ConfirmDeleteView(pin: pin, model: model)
            default:
                PinFormView(model: model, sheet: sheet).id(sheet.id)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.06)))
    }
}

struct ConfirmDeleteView: View {
    let pin: PinnedItem
    @ObservedObject var model: PanelModel

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "trash").font(.system(size: 26)).foregroundStyle(.red)
            Text("“\(pin.label)” sabitini silmek istiyor musunuz?")
                .font(.system(size: 13, weight: .medium)).multilineTextAlignment(.center)
            Text("Bu işlem geri alınamaz.").font(.system(size: 11)).foregroundStyle(.secondary)
            HStack {
                Button("Vazgeç") { model.closeSheet() }
                Button("Sil") {
                    model.core.deletePin(pin)
                    model.closeSheet()
                }
                .keyboardShortcut(.defaultAction)
                .tint(.red)
            }
            Text("↩ sil · esc vazgeç").font(.system(size: 10)).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

struct PinFormView: View {
    @ObservedObject var model: PanelModel
    let sheet: PanelSheet

    @Local private var label = ""
    @Local private var content = ""
    @Local private var secret = false
    @Local private var originalText = ""
    @FocusState private var focus: Field?
    enum Field { case label, content }

    private var heading: String {
        switch sheet {
        case .newPin: return "Yeni sabit"
        case .editPin: return "Sabiti düzenle"
        default: return "Sabitle"
        }
    }
    private var isNew: Bool { if case .newPin = sheet { return true }; return false }
    private var isEdit: Bool { if case .editPin = sheet { return true }; return false }
    private var toggleEnabled: Bool {
        switch sheet {
        case .pinItem(let item, _): return item.kind == .text || item.kind == .link
        case .newPin: return true
        default: return false
        }
    }
    private var editPin: PinnedItem? { if case .editPin(let p) = sheet { return p }; return nil }
    private var showsContentField: Bool {
        if isNew { return true }
        if let p = editPin { return p.isSecret || p.item.kind == .text || p.item.kind == .link }
        return false
    }
    private var canSave: Bool {
        if label.trimmingCharacters(in: .whitespaces).isEmpty { return false }
        if isNew && content.isEmpty { return false }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(heading).font(.system(size: 13, weight: .semibold))
            VStack(alignment: .leading, spacing: 3) {
                Text("Ad").font(.system(size: 11)).foregroundStyle(.secondary)
                TextField("Örn. VPN şifresi", text: $label)
                    .textFieldStyle(.roundedBorder).focused($focus, equals: .label)
                    .onSubmit { if showsContentField && isNew { focus = .content } else { save() } }
            }
            if showsContentField { contentField }
            if !isEdit {
                Toggle("Gizli (içerik görünmez)", isOn: $secret)
                    .disabled(!toggleEnabled)
                    .font(.system(size: 12))
            }
            Spacer(minLength: 0)
            HStack {
                Text("esc vazgeç").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Button("İptal") { model.closeSheet() }
                Button("Kaydet") { save() }
                    .keyboardShortcut(.defaultAction).disabled(!canSave)
            }
        }
        .onAppear(perform: setup)
    }

    @ViewBuilder
    private var contentField: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(isEdit ? "İçerik" : "İçerik").font(.system(size: 11)).foregroundStyle(.secondary)
            let secretNow = isEdit ? (editPin?.isSecret ?? false) : secret
            if secretNow {
                SecureField(isEdit ? "Yeni içerik (boş bırakılırsa değişmez)" : "Gizli içerik", text: $content)
                    .textFieldStyle(.roundedBorder).focused($focus, equals: .content)
                    .onSubmit { save() }
            } else {
                TextField("İçerik", text: $content, axis: .vertical)
                    .lineLimit(1...3)
                    .textFieldStyle(.roundedBorder).focused($focus, equals: .content)
                    .onSubmit { save() }
            }
        }
    }

    private func setup() {
        switch sheet {
        case .pinItem(let item, let sec):
            let t = Fmt.title(of: item)
            label = String(t.prefix(30))
            secret = sec
        case .editPin(let p):
            label = p.label
            if !p.isSecret { content = p.item.text ?? ""; originalText = content }
        default: break
        }
        DispatchQueue.main.async { focus = .label }
    }

    private func save() {
        guard canSave else { return }
        let name = label.trimmingCharacters(in: .whitespaces)
        switch sheet {
        case .pinItem(let item, _):
            model.core.pin(item, label: name, secret: secret && toggleEnabled)
        case .newPin:
            model.core.addPin(label: name, text: content, secret: secret)
        case .editPin(let p):
            var newText: String? = nil
            if p.isSecret { if !content.isEmpty { newText = content } }
            else if content != originalText && !content.isEmpty { newText = content }
            model.core.updatePin(p, label: name, newText: newText)
        default: break
        }
        model.closeSheet()
    }
}
