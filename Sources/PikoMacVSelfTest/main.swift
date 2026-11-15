// Donanım gerektirmeyen mantık testleri. Çalıştırma: swift run PikoMacVSelfTest
import Foundation
import PikoMacVKit
@testable import PikoMacVCore
@testable import PikoMacVInput

nonisolated(unsafe) var failed = 0
func check(_ name: String, _ ok: Bool) {
    print(ok ? "GECTI " : "KALDI ", name)
    if !ok { failed += 1 }
}

// MARK: Dokunmatik yüzey algılayıcısı (sahte MTTouch kareleri)
// Sahte MTTouch kareleri üretir (96 bayt/parmak) ve algılayıcıyı sınar.
func frame(_ fingers: [(id: Int32, state: Int32, x: Float, y: Float)]) -> UnsafeMutableRawPointer {
    let p = UnsafeMutableRawPointer.allocate(byteCount: max(1, fingers.count) * 96, alignment: 8)
    p.initializeMemory(as: UInt8.self, repeating: 0, count: max(1, fingers.count) * 96)
    for (i, f) in fingers.enumerated() {
        let b = p + i * 96
        b.storeBytes(of: f.id, toByteOffset: 16, as: Int32.self)
        b.storeBytes(of: f.state, toByteOffset: 20, as: Int32.self)
        b.storeBytes(of: f.x, toByteOffset: 32, as: Float.self)
        b.storeBytes(of: f.y, toByteOffset: 36, as: Float.self)
    }
    return p
}
final class Box: @unchecked Sendable { var n = 0 }
/// Bir dokunuş: parmaklar sırayla iner, `hold` sn kalır, sırayla kalkar (kalkarken 5/6/7 durumları).
func tap(_ d: TapDetector, dev: UnsafeMutableRawPointer, t: inout Double, fingers n: Int, hold: Double, drift: Float = 0) {
    var act: [(id: Int32, state: Int32, x: Float, y: Float)] = []
    for i in 0..<n {
        act.append((Int32(i + 1), i == 0 ? 2 : 3, 0.3 + Float(i) * 0.15, 0.5))
        d.process(device: dev, touches: frame(act), count: act.count, time: t); t += 0.008
    }
    var steps = Int(hold / 0.008)
    while steps > 0 {
        act = act.map { ($0.id, 4, $0.x + drift / Float(max(1, Int(hold / 0.008))), $0.y) }
        d.process(device: dev, touches: frame(act), count: act.count, time: t); t += 0.008; steps -= 1
    }
    for i in 0..<n {  // kalkış: biri 7'ye geçer, diğerleri sürer
        var f = act; for j in 0...i { f[j].state = 7 }
        d.process(device: dev, touches: frame(f), count: f.count, time: t); t += 0.008
    }
    d.process(device: dev, touches: nil, count: 0, time: t); t += 0.008
}
func run(_ name: String, expect: Int, _ body: (TapDetector, UnsafeMutableRawPointer, inout Double) -> Void) {
    let d = TapDetector(); let box = Box(); d.onDoubleTap = { box.n += 1 }
    var t = 100.0
    body(d, UnsafeMutableRawPointer(bitPattern: 0x1000)!, &t)
    check("dokunma: " + name, box.n == expect)
    if box.n != expect { print(d.diagnostics) }
}
run("3 parmak cift dokunma", expect: 1) { d, dev, t in tap(d, dev: dev, t: &t, fingers: 3, hold: 0.08); t += 0.15; tap(d, dev: dev, t: &t, fingers: 3, hold: 0.08) }
run("3 parmak yavas ama makul (hold 0.2, ara 0.35)", expect: 1) { d, dev, t in tap(d, dev: dev, t: &t, fingers: 3, hold: 0.2); t += 0.35; tap(d, dev: dev, t: &t, fingers: 3, hold: 0.2) }
run("3 parmak tek dokunma", expect: 0) { d, dev, t in tap(d, dev: dev, t: &t, fingers: 3, hold: 0.08) }
run("2 parmak cift dokunma (sag tik)", expect: 0) { d, dev, t in tap(d, dev: dev, t: &t, fingers: 2, hold: 0.08); t += 0.15; tap(d, dev: dev, t: &t, fingers: 2, hold: 0.08) }
run("4 parmak cift dokunma", expect: 0) { d, dev, t in tap(d, dev: dev, t: &t, fingers: 4, hold: 0.08); t += 0.15; tap(d, dev: dev, t: &t, fingers: 4, hold: 0.08) }
run("3 parmak kaydirma (surukleme)", expect: 0) { d, dev, t in tap(d, dev: dev, t: &t, fingers: 3, hold: 0.1, drift: 0.3); t += 0.1; tap(d, dev: dev, t: &t, fingers: 3, hold: 0.1, drift: 0.3) }
run("iki dokunus arasi cok uzun (1 sn)", expect: 0) { d, dev, t in tap(d, dev: dev, t: &t, fingers: 3, hold: 0.08); t += 1.0; tap(d, dev: dev, t: &t, fingers: 3, hold: 0.08) }
run("baska aygit araya giriyor", expect: 1) { d, dev, t in
    let other = UnsafeMutableRawPointer(bitPattern: 0x2000)!
    tap(d, dev: dev, t: &t, fingers: 3, hold: 0.08); d.process(device: other, touches: nil, count: 0, time: t); t += 0.15
    tap(d, dev: dev, t: &t, fingers: 3, hold: 0.08) }
run("uc kez dokunma -> tek tetik", expect: 1) { d, dev, t in for _ in 0..<3 { tap(d, dev: dev, t: &t, fingers: 3, hold: 0.06); t += 0.12 } }

// MARK: Hedef uygulamaya uygunluk kuralları

func item(_ kind: ClipKind, files: [String] = []) -> ClipItem {
    ClipItem(kind: kind, text: kind == .text || kind == .link ? "ornek" : nil,
             files: files.map { FileRef(originalPath: "/tmp/" + $0, name: $0, byteSize: 10, isDirectory: false) }, contentHash: UUID().uuidString)
}
func target(_ bundle: String) -> TargetApp {
    TargetApp(bundleID: bundle, name: bundle, category: TargetRules.category(for: bundle), pid: 0)
}
let word = target("com.microsoft.Word"), finder = target("com.apple.finder"), term = target("com.apple.Terminal")
let code = target("com.microsoft.VSCode"), mail = target("com.apple.mail"), unknown = target("com.ornek.bilinmeyen")

check("kategori: Word belge", word.category == .document)
check("kategori: Finder dosya yöneticisi", finder.category == .fileManager)
check("kategori: Terminal", term.category == .terminal)
check("kategori: VS Code kod editörü", code.category == .codeEditor)
check("kategori: Mail mesajlaşma", mail.category == .messaging)
check("kategori: bilinmeyen diğer", unknown.category == .other)

check("Word: metin uygun", TargetRules.suitability(of: item(.text), for: word)?.mode == .native)
check("Word: görsel uygun", TargetRules.suitability(of: item(.image), for: word)?.mode == .native)
check("Word: bağlantı uygun", TargetRules.suitability(of: item(.link), for: word) != nil)
check("Word: pdf dosyası uygun değil", TargetRules.suitability(of: item(.file, files: ["rapor.pdf"]), for: word) == nil)
check("Word: tek görsel dosyası görsel olarak", TargetRules.suitability(of: item(.file, files: ["logo.png"]), for: word)?.hint == "görsel olarak")
check("Word: iki görsel dosyası uygun değil", TargetRules.suitability(of: item(.file, files: ["a.png", "b.png"]), for: word) == nil)
check("Finder: dosya uygun", TargetRules.suitability(of: item(.file, files: ["rapor.pdf"]), for: finder)?.mode == .native)
check("Finder: görsel dosya olarak", TargetRules.suitability(of: item(.image), for: finder) == Suitability(mode: .asFile, hint: "dosya olarak"))
check("Finder: metin uygun değil", TargetRules.suitability(of: item(.text), for: finder) == nil)
check("Terminal: metin düz metin", TargetRules.suitability(of: item(.text), for: term)?.mode == .plainText)
check("Terminal: dosya yol olarak", TargetRules.suitability(of: item(.file, files: ["a.txt"]), for: term) == Suitability(mode: .asPath, hint: "yol olarak"))
check("Terminal: görsel uygun değil", TargetRules.suitability(of: item(.image), for: term) == nil)
check("VS Code: dosya yol olarak", TargetRules.suitability(of: item(.file, files: ["a.txt"]), for: code)?.mode == .asPath)
check("Mail: dosya ek olarak", TargetRules.suitability(of: item(.file, files: ["a.pdf"]), for: mail)?.hint == "ek olarak")
for k in ClipKind.allCases {
    check("bilinmeyen uygulama: \(k.rawValue) uygun", TargetRules.suitability(of: item(k, files: k == .file ? ["a.pdf"] : []), for: unknown) != nil)
    check("hedef yok: \(k.rawValue) uygun", TargetRules.suitability(of: item(k, files: k == .file ? ["a.pdf"] : []), for: nil) != nil)
}

print(failed == 0 ? "\nTum testler gecti." : "\n\(failed) test KALDI.")
exit(failed == 0 ? 0 : 1)
