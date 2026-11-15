import AppKit
import PikoMacVKit

typealias PikoMacVBinding = PikoMacVKit.Binding

enum Fmt {
    static func relative(_ date: Date, now: Date = Date()) -> String {
        let s = Int(now.timeIntervalSince(date))
        if s < 60 { return "şimdi" }
        if s < 3600 { return "\(s / 60) dk" }
        if s < 86400 { return "\(s / 3600) sa" }
        let cal = Calendar.current
        if cal.isDateInYesterday(date) { return "dün" }
        let days = max(2, cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: now)).day ?? 2)
        if days < 30 { return "\(days) gün" }
        if days < 365 { return "\(days / 30) ay" }
        return "\(days / 365) yıl"
    }

    static func bytes(_ n: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: n)
    }

    private static let numberFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.maximumFractionDigits = 1
        f.minimumFractionDigits = 0
        return f
    }()

    static func number(_ v: Double) -> String { numberFormatter.string(from: NSNumber(value: v)) ?? "\(v)" }

    /// "2,7 / 3 GB"
    static func storage(used: Int64, cap: Int64) -> String {
        let gb = 1024.0 * 1024 * 1024
        let u = Double(used)
        let usedText = u < gb ? "\(number(u / (1024 * 1024))) MB" : number(u / gb)
        let capText = number(Double(cap) / gb)
        if u < gb { return "\(usedText) / \(capText) GB" }
        return "\(usedText) / \(capText) GB"
    }

    static func collapse(_ s: String, limit: Int = 200) -> String {
        let joined = s.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
        let t = joined.trimmingCharacters(in: .whitespaces)
        return t.count > limit ? String(t.prefix(limit)) : t
    }

    static func title(of item: ClipItem) -> String {
        switch item.kind {
        case .text, .link:
            let t = collapse(item.text ?? "")
            return t.isEmpty ? "(boş metin)" : t
        case .image:
            if let w = item.imageWidth, let h = item.imageHeight { return "Görsel \(w) × \(h)" }
            return "Görsel"
        case .file:
            if item.files.count == 1 { return item.files[0].name }
            let names = item.files.prefix(3).map(\.name).joined(separator: ", ")
            return "\(item.files.count) dosya: \(names)"
        }
    }

    static func symbol(of kind: ClipKind) -> String {
        switch kind {
        case .text: return "textformat"
        case .link: return "link"
        case .image: return "photo"
        case .file: return "doc"
        }
    }

    static func carbonMask(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= 0x100 }
        if flags.contains(.shift) { m |= 0x200 }
        if flags.contains(.option) { m |= 0x800 }
        if flags.contains(.control) { m |= 0x1000 }
        return m
    }
}
