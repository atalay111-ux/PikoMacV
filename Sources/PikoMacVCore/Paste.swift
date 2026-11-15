import AppKit
import ApplicationServices
import PikoMacVKit

extension CoreServices {
    public func paste(_ item: ClipItem, mode: PasteMode, into target: TargetApp?) {
        writePasteboard(item, mode: mode)
        if let idx = state.items.firstIndex(where: { $0.id == item.id }), idx != 0 {
            let it = state.items.remove(at: idx)
            state.items.insert(it, at: 0)
            itemsChanged()
        }
        sendPaste(to: target)
    }

    public func paste(_ pin: PinnedItem, mode: PasteMode, into target: TargetApp?) {
        if pin.isSecret {
            guard let secret = SecretStore.get(account: pin.id.uuidString) else { NSSound.beep(); return }
            let pb = NSPasteboard.general
            pb.clearContents()
            let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
            pb.declareTypes([.string, concealed], owner: nil)
            pb.setString(secret, forType: .string)
            pb.setString("", forType: concealed)
            let own = pb.changeCount
            ownChangeCount = own
            let delay = state.settings.secretClipboardClearSeconds
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                let p = NSPasteboard.general
                if p.changeCount == own { p.clearContents() }
            }
        } else {
            writePasteboard(pin.item, mode: mode)
        }
        sendPaste(to: target)
    }

    // MARK: - PikoMacV yazımı

    private func writePasteboard(_ item: ClipItem, mode: PasteMode) {
        let pb = NSPasteboard.general
        switch item.kind {
        case .text, .link:
            pb.clearContents()
            guard let text = item.text else { break }
            pb.setString(text, forType: .string)
            if mode != .plainText, let r = item.rtfBlob, let d = try? Data(contentsOf: paths.blobURL(r)) {
                pb.setData(d, forType: .rtf)
            }
        case .image:
            guard let b = item.imageBlob, let png = try? Data(contentsOf: paths.blobURL(b)) else { pb.clearContents(); break }
            if mode == .asFile {
                let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"
                let url = paths.cache.appendingPathComponent("PikoMacV-\(f.string(from: Date())).png")
                try? FileManager.default.createDirectory(at: paths.cache, withIntermediateDirectories: true)
                pb.clearContents()
                if (try? png.write(to: url, options: .atomic)) != nil { pb.writeObjects([url as NSURL]) }
            } else {
                pb.clearContents()
                pb.setData(png, forType: .png)
                if let tiff = NSImage(data: png)?.tiffRepresentation { pb.setData(tiff, forType: .tiff) }
            }
        case .file:
            let urls = resolvedURLs(item)
            pb.clearContents()
            if mode == .asPath {
                pb.setString(urls.map { shellEscape($0.path) }.joined(separator: " "), forType: .string)
            } else if !urls.isEmpty {
                pb.writeObjects(urls.map { $0 as NSURL })
            }
        }
        ownChangeCount = pb.changeCount
    }

    private func resolvedURLs(_ item: ClipItem) -> [URL] {
        let fm = FileManager.default
        return item.files.compactMap { f in
            if fm.fileExists(atPath: f.originalPath) { return URL(fileURLWithPath: f.originalPath) }
            if let s = f.storedCopy, fm.fileExists(atPath: paths.vaultURL(s).path) { return paths.vaultURL(s) }
            return nil
        }
    }

    private func shellEscape(_ s: String) -> String {
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._-+=:,@%")
        if !s.isEmpty, s.unicodeScalars.allSatisfy({ safe.contains($0) }) { return s }
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - ⌘V

    private func sendPaste(to target: TargetApp?) {
        guard let target else { return }
        NSRunningApplication(processIdentifier: target.pid)?.activate()
        guard AXIsProcessTrusted() else { return }   // içerik panoda kalır
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            let src = CGEventSource(stateID: .combinedSessionState)
            let down = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true)
            let up = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
            down?.flags = .maskCommand
            up?.flags = .maskCommand
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
    }
}
