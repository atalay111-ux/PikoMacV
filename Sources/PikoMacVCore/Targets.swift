import Foundation
import PikoMacVKit

/// Uygulama kategorisi tabloları ve uygunluk kuralları.
enum TargetRules {
    private static let exact: [String: AppCategory] = [
        "com.apple.finder": .fileManager, "com.cocoatech.PathFinder": .fileManager,
        "com.apple.Terminal": .terminal, "com.googlecode.iterm2": .terminal, "dev.warp.Warp-Stable": .terminal,
        "dev.warp.Warp": .terminal, "com.mitchellh.ghostty": .terminal, "net.kovidgoyal.kitty": .terminal,
        "org.alacritty": .terminal, "co.zeit.hyper": .terminal, "com.github.wez.wezterm": .terminal,
        "com.microsoft.VSCode": .codeEditor, "com.microsoft.VSCodeInsiders": .codeEditor,
        "com.apple.dt.Xcode": .codeEditor, "dev.zed.Zed": .codeEditor, "dev.zed.Zed-Preview": .codeEditor,
        "com.todesktop.230313mzl4w4u92": .codeEditor, "com.vscodium": .codeEditor,
        "com.panic.Nova": .codeEditor, "com.github.atom": .codeEditor, "com.barebones.bbedit": .codeEditor,
        "com.microsoft.Word": .document, "com.microsoft.Excel": .document, "com.microsoft.Powerpoint": .document,
        "com.apple.Notes": .document, "com.apple.TextEdit": .document, "com.microsoft.onenote.mac": .document,
        "md.obsidian": .document, "notion.id": .document, "com.apple.Preview": .document,
        "com.apple.mail": .messaging, "com.microsoft.Outlook": .messaging, "com.tinyspeck.slackmacgap": .messaging,
        "net.whatsapp.WhatsApp": .messaging, "com.microsoft.teams2": .messaging, "com.microsoft.teams": .messaging,
        "ru.keepcoder.Telegram": .messaging, "org.telegram.desktop": .messaging, "com.hnc.Discord": .messaging,
        "com.apple.MobileSMS": .messaging, "org.whispersystems.signal-desktop": .messaging,
        "com.apple.Safari": .browser, "com.google.Chrome": .browser, "org.mozilla.firefox": .browser,
        "com.microsoft.edgemac": .browser, "company.thebrowser.Browser": .browser,
        "com.brave.Browser": .browser, "com.operasoftware.Opera": .browser, "com.vivaldi.Vivaldi": .browser,
    ]
    private static let prefixes: [(String, AppCategory)] = [
        ("com.binarynights.ForkLift", .fileManager),
        ("com.jetbrains.", .codeEditor), ("com.sublimetext.", .codeEditor),
        ("com.apple.iWork.", .document),
        ("com.apple.Safari", .browser), ("com.google.Chrome", .browser),
    ]

    static func category(for bundleID: String?) -> AppCategory {
        guard let id = bundleID else { return .other }
        if let c = exact[id] { return c }
        for (p, c) in prefixes where id.hasPrefix(p) { return c }
        return .other
    }

    private static let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "tiff", "webp"]

    static func suitability(of item: ClipItem, for target: TargetApp?) -> Suitability? {
        let cat = target?.category ?? .other
        switch cat {
        case .other, .browser:
            return Suitability(mode: .native)
        case .messaging:
            return Suitability(mode: .native, hint: item.kind == .file ? "ek olarak" : nil)
        case .document:
            switch item.kind {
            case .text, .link, .image: return Suitability(mode: .native)
            case .file:
                if item.files.count == 1, let f = item.files.first, !f.isDirectory,
                   imageExts.contains((f.name as NSString).pathExtension.lowercased()) {
                    return Suitability(mode: .native, hint: "görsel olarak")
                }
                return nil
            }
        case .fileManager:
            switch item.kind {
            case .file: return Suitability(mode: .native)
            case .image: return Suitability(mode: .asFile, hint: "dosya olarak")
            case .text, .link: return nil
            }
        case .terminal, .codeEditor:
            switch item.kind {
            case .text, .link: return Suitability(mode: cat == .terminal ? .plainText : .native)
            case .file: return Suitability(mode: .asPath, hint: "yol olarak")
            case .image: return nil
            }
        }
    }
}
