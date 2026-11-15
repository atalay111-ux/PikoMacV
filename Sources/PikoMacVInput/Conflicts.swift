import Carbon
import Foundation

enum Conflicts {
    private static let relevantMask = UInt32(cmdKey | optionKey | controlKey | shiftKey)

    private static func cocoaToCarbon(_ f: Int) -> UInt32 {
        var m: UInt32 = 0
        if f & (1 << 17) != 0 { m |= UInt32(shiftKey) }
        if f & (1 << 18) != 0 { m |= UInt32(controlKey) }
        if f & (1 << 19) != 0 { m |= UInt32(optionKey) }
        if f & (1 << 20) != 0 { m |= UInt32(cmdKey) }
        return m
    }

    private static let names: [Int: String] = [
        64: "Spotlight", 65: "Finder araması", 28: "Ekran görüntüsü", 29: "Ekran görüntüsü", 30: "Ekran görüntüsü",
        31: "Ekran görüntüsü", 184: "Ekran görüntüsü ve kayıt", 32: "Mission Control", 33: "Mission Control",
        34: "Mission Control", 35: "Mission Control", 36: "Mission Control", 37: "Mission Control",
        60: "Girdi kaynağı değiştirme", 61: "Girdi kaynağı değiştirme", 160: "Launchpad", 52: "Dock'u gizle/göster",
        79: "Masaüstü değiştirme", 80: "Masaüstü değiştirme", 81: "Masaüstü değiştirme", 82: "Masaüstü değiştirme",
        118: "Masaüstü 1'e geç", 119: "Masaüstü 2'ye geç", 120: "Masaüstü 3'e geç", 121: "Masaüstü 4'e geç",
        7: "Odak: menü çubuğu", 8: "Odak: Dock", 27: "Pencereler arası geçiş", 98: "Yardım menüsü",
    ]

    static func system(keyCode: UInt32, modifiers: UInt32) -> String? {
        guard let all = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, "com.apple.symbolichotkeys" as CFString) as? [String: Any] else { return nil }
        for (idStr, v) in all {
            guard let entry = v as? [String: Any], (entry["enabled"] as? Bool) ?? ((entry["enabled"] as? Int ?? 0) != 0),
                  let value = entry["value"] as? [String: Any], let params = value["parameters"] as? [Any], params.count >= 3,
                  let kc = (params[1] as? NSNumber)?.intValue, let mod = (params[2] as? NSNumber)?.intValue else { continue }
            if kc == 65535 { continue }
            if UInt32(kc) == keyCode && cocoaToCarbon(mod) == (modifiers & relevantMask) {
                return "Sistem kısayolu: " + (names[Int(idStr) ?? -1] ?? "Sistem kısayolu")
            }
        }
        return nil
    }

    private static let c = UInt32(cmdKey), s = UInt32(shiftKey), o = UInt32(optionKey)

    private static let common: [UInt64: String] = {
        func k(_ code: UInt32, _ mods: UInt32) -> UInt64 { UInt64(code) << 32 | UInt64(mods) }
        return [
            k(8, c): "Kopyala (⌘C)", k(9, c): "Yapıştır (⌘V)", k(7, c): "Kes (⌘X)", k(6, c): "Geri al (⌘Z)",
            k(0, c): "Tümünü seç (⌘A)", k(1, c): "Kaydet (⌘S)", k(12, c): "Çık (⌘Q)", k(13, c): "Pencereyi kapat (⌘W)",
            k(17, c): "Yeni sekme (⌘T)", k(45, c): "Yeni (⌘N)", k(3, c): "Bul (⌘F)", k(35, c): "Yazdır (⌘P)",
            k(48, c): "Uygulama değiştirici (⌘Tab)", k(49, c): "Spotlight (⌘Boşluk)",
            k(9, c | s): "Birçok uygulamada biçimsiz yapıştır", k(9, c | o): "Finder'da taşı",
            k(20, c | s): "Ekran görüntüsü", k(21, c | s): "Ekran görüntüsü", k(23, c | s): "Ekran görüntüsü",
            k(6, c | s): "Yinele (⌘⇧Z)",
        ]
    }()

    static func common(keyCode: UInt32, modifiers: UInt32) -> String? {
        common[UInt64(keyCode) << 32 | UInt64(modifiers & relevantMask)]
    }
}
