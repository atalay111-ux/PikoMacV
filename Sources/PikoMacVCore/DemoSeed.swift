import AppKit
import PikoMacVKit

extension CoreServices {
    /// Belge ekran görüntüleri için uydurma veri. Yalnızca `PIKOMACV_DATA_DIR` verilmişse çalışır
    /// (gerçek veri klasörüne asla yazmaz). Mevcut demo verisinin üstüne yazar.
    public func seedDemo() {
        guard ProcessInfo.processInfo.environment["PIKOMACV_DATA_DIR"]?.isEmpty == false else { return }
        let fm = FileManager.default
        try? fm.removeItem(at: paths.blobs)
        try? fm.removeItem(at: paths.vault)
        paths.prepare()

        let now = Date()
        func ago(_ seconds: TimeInterval) -> Date { now.addingTimeInterval(-seconds) }
        let min = 60.0, hour = 3600.0, day = 86400.0
        let mb: Int64 = 1024 * 1024

        func text(_ t: String, app: String, bundle: String, at: Date, kind: ClipKind = .text) -> ClipItem {
            ClipItem(kind: kind, createdAt: at, sourceAppName: app, sourceBundleID: bundle, text: t,
                     contentHash: Hashing.hex("text:" + t))
        }
        func vaultFile(_ name: String, size: Int64) -> FileRef {
            let sub = UUID().uuidString
            let dir = paths.vault.appendingPathComponent(sub, isDirectory: true)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try? Data("demo".utf8).write(to: dir.appendingPathComponent(name))
            return FileRef(originalPath: "/Users/demo/Belgeler/" + name, name: name, byteSize: size,
                           isDirectory: false, storedCopy: sub + "/" + name)
        }
        func fileItem(_ files: [FileRef], app: String, bundle: String, at: Date) -> ClipItem {
            ClipItem(kind: .file, createdAt: at, sourceAppName: app, sourceBundleID: bundle, files: files,
                     contentHash: Hashing.hex("file:" + files.map(\.name).joined(separator: ",") + "\(at.timeIntervalSince1970)"))
        }

        // Görsel: hoş bir degrade.
        let (w, h) = (640, 400)
        let imgName = UUID().uuidString + ".png"
        if let png = Self.demoPNG(width: w, height: h) { try? png.write(to: paths.blobURL(imgName)) }

        var items: [ClipItem] = []
        items.append(text("Toplantı notlarını yarın sabaha kadar paylaşırım, uygun mu?", app: "Mail", bundle: "com.apple.mail", at: ago(3 * min)))
        items.append(text("git log --oneline --since=\"1 week ago\" | head -20", app: "Terminal", bundle: "com.apple.Terminal", at: ago(14 * min)))
        items.append(text("https://example.com/fiyat-listesi", app: "Safari", bundle: "com.apple.Safari", at: ago(38 * min), kind: .link))
        items.append(fileItem([vaultFile("Rapor-2026.pdf", size: Int64(2.4 * Double(mb)))], app: "Finder", bundle: "com.apple.finder", at: ago(3 * hour)))
        items.append(text("Örnek Mah. Deneme Sok. No: 12 Daire 4, 34000 İstanbul", app: "Notlar", bundle: "com.apple.Notes", at: ago(5 * hour)))
        items.append(fileItem([vaultFile("logo.png", size: 180 * 1024), vaultFile("sunum.key", size: 14 * mb),
                               vaultFile("veri.xlsx", size: 3 * mb)], app: "Finder", bundle: "com.apple.finder", at: ago(1 * day + 2 * hour)))
        items.append(ClipItem(kind: .image, createdAt: ago(1.5 * hour), sourceAppName: "Önizleme", sourceBundleID: "com.apple.Preview",
                              imageBlob: imgName, imageWidth: w, imageHeight: h, contentHash: Hashing.hex("img-demo")))
        items.append(text("Merhaba, fiyat teklifimizi ekte bulabilirsiniz. İyi çalışmalar dilerim.", app: "Mail", bundle: "com.apple.mail", at: ago(2 * day)))
        items.append(fileItem([vaultFile("Ekran kaydı.mov", size: 96 * mb)], app: "Finder", bundle: "com.apple.finder", at: ago(9 * day)))
        // Depo doluluğunu ~2,7 / 3 GB yapan eski, büyük bir arşiv (yalnızca üst veri büyük).
        items.append(fileItem([vaultFile("Tasarım arşivi.zip", size: 2_600 * mb)], app: "Finder", bundle: "com.apple.finder", at: ago(21 * day)))

        func pinItem(_ label: String, _ item: ClipItem, secret: Bool = false, id: UUID = UUID()) -> PinnedItem {
            PinnedItem(id: id, label: label, isSecret: secret, item: item, createdAt: ago(30 * day))
        }
        var pins: [PinnedItem] = []
        for (label, value) in [("VPN şifresi", "demo-vpn-Parola-4821"), ("Test paneli girişi", "demo-panel-Parola-1937")] {
            let id = UUID()
            SecretStore.set(value, account: id.uuidString)
            pins.append(pinItem(label, ClipItem(kind: .text, contentHash: UUID().uuidString), secret: true, id: id))
        }
        let sig = "Saygılarımla,\nAyşe Örnek\nSatış Danışmanı · Örnek A.Ş."
        pins.append(pinItem("E-posta imzası", ClipItem(kind: .text, text: sig, contentHash: Hashing.hex("text:" + sig))))
        let addr = "Örnek A.Ş., Deneme Cad. No: 7, Kat 3, 34000 İstanbul"
        pins.append(pinItem("Şirket adresi", ClipItem(kind: .text, text: addr, contentHash: Hashing.hex("text:" + addr))))
        pins.append(pinItem("Antetli kağıt.docx", fileItem([vaultFile("Antetli kağıt.docx", size: 48 * 1024)], app: "Finder", bundle: "com.apple.finder", at: ago(30 * day))))

        var settings = Settings()
        settings.onboardingDone = true
        settings.historyLimit = 200
        settings.bindings = [
            Binding(mode: .general, trigger: .keyboard(keyCode: 9, modifiers: 0x1900)),   // ⌃⌥⌘V
            Binding(mode: .pinned, trigger: .keyboard(keyCode: 35, modifiers: 0x1900)),   // ⌃⌥⌘P
        ]
        state.items = items
        state.pins = pins
        state.settings = settings
        recomputeVault()
        saveNow()
    }

    private static func demoPNG(width: Int, height: Int) -> Data? {
        let img = NSImage(size: NSSize(width: width, height: height), flipped: false) { r in
            NSGradient(colors: [NSColor(red: 0.36, green: 0.55, blue: 0.95, alpha: 1), NSColor(red: 0.80, green: 0.45, blue: 0.85, alpha: 1),
                                NSColor(red: 0.98, green: 0.65, blue: 0.45, alpha: 1)])?.draw(in: r, angle: 35)
            NSColor.white.withAlphaComponent(0.22).setFill()
            NSBezierPath(ovalIn: NSRect(x: 360, y: 120, width: 360, height: 360)).fill()
            NSColor.white.withAlphaComponent(0.16).setFill()
            NSBezierPath(ovalIn: NSRect(x: -80, y: -120, width: 380, height: 380)).fill()
            NSColor.white.withAlphaComponent(0.9).setFill()
            NSBezierPath(roundedRect: NSRect(x: 200, y: 140, width: 240, height: 120), xRadius: 24, yRadius: 24).fill()
            return true
        }
        guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
