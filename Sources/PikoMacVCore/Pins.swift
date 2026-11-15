import AppKit
import LocalAuthentication
import PikoMacVKit

extension CoreServices {
    // MARK: - Sabitler

    public func pin(_ item: ClipItem, label: String, secret: Bool) {
        let pinID = UUID()
        var copy = duplicate(item)
        let canSecret = secret && (item.kind == .text || item.kind == .link) && item.text != nil
        if canSecret, let text = item.text {
            SecretStore.set(text, account: pinID.uuidString)
            deleteAssets(of: copy)
            copy.text = nil
            copy.rtfBlob = nil
            copy.contentHash = UUID().uuidString
        }
        state.pins.append(PinnedItem(id: pinID, label: label, isSecret: canSecret, item: copy))
        itemsChanged()
        // Gizli sabitlenen öğenin düz metni geçmişte kalmasın.
        if canSecret, state.items.contains(where: { $0.id == item.id }) { delete(item) }
    }

    public func addPin(label: String, text: String, secret: Bool) {
        let pinID = UUID()
        var item = ClipItem(kind: .text, text: text, contentHash: Hashing.hex("text:" + text))
        if secret {
            SecretStore.set(text, account: pinID.uuidString)
            item.text = nil
            item.contentHash = UUID().uuidString
        }
        state.pins.append(PinnedItem(id: pinID, label: label, isSecret: secret, item: item))
        itemsChanged()
    }

    public func updatePin(_ pin: PinnedItem, label: String, newText: String?) {
        guard let idx = state.pins.firstIndex(where: { $0.id == pin.id }) else { return }
        state.pins[idx].label = label
        if let newText {
            if state.pins[idx].isSecret {
                SecretStore.set(newText, account: pin.id.uuidString)
            } else if state.pins[idx].item.kind == .text || state.pins[idx].item.kind == .link {
                if let r = state.pins[idx].item.rtfBlob { try? FileManager.default.removeItem(at: paths.blobURL(r)) }
                state.pins[idx].item.rtfBlob = nil
                state.pins[idx].item.text = newText
                state.pins[idx].item.contentHash = Hashing.hex("text:" + newText)
            }
        }
        itemsChanged()
    }

    public func deletePin(_ pin: PinnedItem) {
        guard let idx = state.pins.firstIndex(where: { $0.id == pin.id }) else { return }
        let removed = state.pins.remove(at: idx)
        if removed.isSecret { SecretStore.delete(account: removed.id.uuidString) }
        deleteAssets(of: removed.item)
        itemsChanged()
    }

    public func movePins(fromOffsets: IndexSet, toOffset: Int) {
        let moving = fromOffsets.sorted().filter { $0 < state.pins.count }.map { state.pins[$0] }
        var rest = state.pins
        for i in fromOffsets.sorted(by: >) where i < rest.count { rest.remove(at: i) }
        let insertAt = max(0, min(rest.count, toOffset - fromOffsets.filter { $0 < toOffset }.count))
        rest.insert(contentsOf: moving, at: insertAt)
        state.pins = rest
        itemsChanged()
    }

    /// Sabit için bağımsız kopya: yeni kimlik, blob ve depo kopyaları çoğaltılır.
    private func duplicate(_ item: ClipItem) -> ClipItem {
        var c = item
        c.id = UUID()
        let fm = FileManager.default
        if let b = item.imageBlob, !b.isEmpty {
            let n = UUID().uuidString + ".png"
            if (try? fm.copyItem(at: paths.blobURL(b), to: paths.blobURL(n))) != nil { c.imageBlob = n } else { c.imageBlob = nil }
        }
        if let r = item.rtfBlob {
            let n = UUID().uuidString + ".rtf"
            if (try? fm.copyItem(at: paths.blobURL(r), to: paths.blobURL(n))) != nil { c.rtfBlob = n } else { c.rtfBlob = nil }
        }
        c.files = item.files.map { f in
            var nf = f
            nf.storedCopy = nil
            guard let s = f.storedCopy else { return nf }
            let src = paths.vaultURL(s)
            let sub = UUID().uuidString
            let dir = paths.vault.appendingPathComponent(sub, isDirectory: true)
            let dst = dir.appendingPathComponent(src.lastPathComponent)
            do {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                // Sabit bağ: anında ve bağımsız silinebilir; olmazsa kopyala.
                do { try fm.linkItem(at: src, to: dst) } catch { try fm.copyItem(at: src, to: dst) }
                nf.storedCopy = sub + "/" + src.lastPathComponent
            } catch {
                try? fm.removeItem(at: dir)
            }
            return nf
        }
        return c
    }

    // MARK: - Gizli sabit

    public func revealSecret(_ pin: PinnedItem) async -> String? {
        guard pin.isSecret else { return pin.item.text }
        let window = state.settings.secretSessionSeconds
        if let t = lastAuth, Date().timeIntervalSince(t) < window {
            return SecretStore.get(account: pin.id.uuidString)
        }
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { return nil }
        do {
            let ok = try await ctx.evaluatePolicy(.deviceOwnerAuthentication,
                                                  localizedReason: "gizli sabiti göstermek için")
            guard ok else { return nil }
            lastAuth = Date()
            return SecretStore.get(account: pin.id.uuidString)
        } catch {
            return nil
        }
    }
}
