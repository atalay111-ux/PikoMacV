import AppKit
import Combine
import Foundation

// MARK: - Modeller

public enum ClipKind: String, Codable, CaseIterable, Sendable {
    case text, image, file, link
}

public struct FileRef: Codable, Equatable, Sendable {
    public var originalPath: String
    public var name: String
    public var byteSize: Int64
    public var isDirectory: Bool
    /// Dosya deposundaki kopyanın adı. Kopya tutulmadıysa (boyut sınırı, klasör) nil.
    public var storedCopy: String?

    public init(originalPath: String, name: String, byteSize: Int64, isDirectory: Bool, storedCopy: String? = nil) {
        self.originalPath = originalPath
        self.name = name
        self.byteSize = byteSize
        self.isDirectory = isDirectory
        self.storedCopy = storedCopy
    }
}

public struct ClipItem: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var kind: ClipKind
    public var createdAt: Date
    public var sourceAppName: String?
    public var sourceBundleID: String?
    /// .text ve .link için içerik. Gizli sabitlerde her zaman nil (içerik Anahtar Zinciri'nde).
    public var text: String?
    /// Zengin metin (RTF) verisinin depodaki dosya adı; yoksa nil.
    public var rtfBlob: String?
    /// .image için PNG verisinin depodaki dosya adı.
    public var imageBlob: String?
    public var imageWidth: Int?
    public var imageHeight: Int?
    /// .file için kopyalanan dosyalar.
    public var files: [FileRef]
    /// Yinelenenleri ayıklamak için içerik özeti.
    public var contentHash: String

    public init(id: UUID = UUID(), kind: ClipKind, createdAt: Date = Date(), sourceAppName: String? = nil,
                sourceBundleID: String? = nil, text: String? = nil, rtfBlob: String? = nil, imageBlob: String? = nil,
                imageWidth: Int? = nil, imageHeight: Int? = nil, files: [FileRef] = [], contentHash: String) {
        self.id = id; self.kind = kind; self.createdAt = createdAt
        self.sourceAppName = sourceAppName; self.sourceBundleID = sourceBundleID
        self.text = text; self.rtfBlob = rtfBlob; self.imageBlob = imageBlob
        self.imageWidth = imageWidth; self.imageHeight = imageHeight
        self.files = files; self.contentHash = contentHash
    }

    /// Dosya deposunda kapladığı toplam bayt (yalnızca kopyası tutulan dosyalar).
    public var storedBytes: Int64 { files.filter { $0.storedCopy != nil }.reduce(0) { $0 + $1.byteSize } }
}

public struct PinnedItem: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    /// Kullanıcının verdiği görünen ad ("VPN şifresi").
    public var label: String
    public var isSecret: Bool
    public var item: ClipItem
    public var createdAt: Date

    public init(id: UUID = UUID(), label: String, isSecret: Bool, item: ClipItem, createdAt: Date = Date()) {
        self.id = id; self.label = label; self.isSecret = isSecret; self.item = item; self.createdAt = createdAt
    }
}

// MARK: - Hedef uygulama ve uygunluk

public enum AppCategory: String, Sendable {
    case document      // Word, Pages, Notlar, TextEdit...
    case fileManager   // Finder, Path Finder...
    case terminal      // Terminal, iTerm, Warp...
    case codeEditor    // VS Code, Xcode, JetBrains...
    case messaging     // Mail, Slack, WhatsApp, Teams...
    case browser
    case other
}

public struct TargetApp: Equatable, Sendable {
    public var bundleID: String?
    public var name: String
    public var category: AppCategory
    public var pid: pid_t

    public init(bundleID: String?, name: String, category: AppCategory, pid: pid_t) {
        self.bundleID = bundleID; self.name = name; self.category = category; self.pid = pid
    }
}

public enum PasteMode: String, Sendable {
    case native      // türün kendi biçimi
    case plainText   // biçimsiz metin
    case asFile      // görseli dosya olarak
    case asPath      // dosyayı yol metni olarak
}

/// Bir öğenin hedef uygulamaya nasıl yapışacağı. Uygun değilse `suitability` nil döner.
public struct Suitability: Equatable, Sendable {
    public var mode: PasteMode
    /// Satırda gösterilecek kısa not: "dosya olarak", "yol olarak"; yoksa nil.
    public var hint: String?
    public init(mode: PasteMode, hint: String? = nil) { self.mode = mode; self.hint = hint }
}

// MARK: - Tetikleyiciler

public enum PanelMode: String, Codable, Sendable, CaseIterable {
    case general, pinned
}

public enum Trigger: Codable, Hashable, Sendable {
    /// Carbon sanal tuş kodu ve Carbon değiştirici maskesi (cmdKey, optionKey, controlKey, shiftKey).
    case keyboard(keyCode: UInt32, modifiers: UInt32)
    /// Fare tuş numarası: 2 = orta tuş, 3 ve 4 = yan tuşlar...
    case mouseButton(Int)
    case trackpadThreeFingerDoubleTap
}

public struct Binding: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var mode: PanelMode
    public var trigger: Trigger
    public init(id: UUID = UUID(), mode: PanelMode, trigger: Trigger) {
        self.id = id; self.mode = mode; self.trigger = trigger
    }
}

// MARK: - Ayarlar

public struct Settings: Codable, Equatable, Sendable {
    public var historyLimit: Int = 200
    public var maxFileCopyBytes: Int64 = 100 * 1024 * 1024
    public var vaultCapBytes: Int64 = 3 * 1024 * 1024 * 1024
    /// Touch ID doğrulamasının geçerli kaldığı süre.
    public var secretSessionSeconds: Double = 2 * 60 * 60
    /// Gizli öğe yapıştırıldıktan sonra panodan silinme süresi.
    public var secretClipboardClearSeconds: Double = 30
    public var bindings: [Binding] = []
    public var onboardingDone: Bool = false
    public var launchAtLogin: Bool = false
    /// Kopyaladıkları geçmişe alınmayan uygulamalar.
    public var ignoredBundleIDs: [String] = []
    public init() {}
}

// MARK: - Paylaşılan durum

/// Tek doğruluk kaynağı. PikoMacVCore yazar, PikoMacVUI okur ve gözlemler.
@MainActor
public final class AppState: ObservableObject {
    /// En yeni öğe başta.
    @Published public var items: [ClipItem] = []
    @Published public var pins: [PinnedItem] = []
    @Published public var settings = Settings()
    @Published public var vaultUsedBytes: Int64 = 0
    public init() {}
}

// MARK: - Servis sözleşmeleri

/// PikoMacVCore tarafından uygulanır (`CoreServices`).
@MainActor
public protocol CoreActions: AnyObject {
    /// Panel kapatıldıktan sonra çağrılır; öğeyi panoya yazar ve hedef uygulamaya ⌘V gönderir.
    func paste(_ item: ClipItem, mode: PasteMode, into target: TargetApp?)
    /// Gizli sabitlerde içerik Anahtar Zinciri'nden okunur, doğrulama istenmez, pano süre sonunda temizlenir.
    func paste(_ pin: PinnedItem, mode: PasteMode, into target: TargetApp?)

    func delete(_ item: ClipItem)
    func clearHistory()

    func pin(_ item: ClipItem, label: String, secret: Bool)
    func addPin(label: String, text: String, secret: Bool)
    /// `newText` nil ise yalnızca etiket değişir.
    func updatePin(_ pin: PinnedItem, label: String, newText: String?)
    func deletePin(_ pin: PinnedItem)
    func movePins(fromOffsets: IndexSet, toOffset: Int)

    /// Touch ID / parola ister (oturum süresi içinde tekrar sormaz). Reddedilirse nil.
    func revealSecret(_ pin: PinnedItem) async -> String?

    /// Panel açılmadan hemen önce öndeki uygulama.
    func currentTarget() -> TargetApp?
    func suitability(of item: ClipItem, for target: TargetApp?) -> Suitability?
    /// 0 = güvende, 1 = sıradaki silinecek. Kopyası olmayan öğelerde 0.
    func evictionRisk(of item: ClipItem) -> Double
    func thumbnail(for item: ClipItem) -> NSImage?
    /// Dosyanın kopyası ya da özgün konumu hâlâ erişilebilir mi.
    func isAvailable(_ item: ClipItem) -> Bool

    /// `state.settings` değiştikten sonra çağrılır: kaydeder, sınırları uygular.
    func settingsChanged()
}

/// PikoMacVInput tarafından uygulanır (`InputServices`).
@MainActor
public protocol InputActions: AnyObject {
    var onTrigger: ((PanelMode) -> Void)? { get set }
    /// Tüm tetikleyicileri yeniden kurar. Kurulamayanları neden metniyle (Türkçe) döndürür.
    @discardableResult func apply(bindings: [Binding]) -> [UUID: String]
    /// Boşta görünen klavye kısayolu önerileri.
    func suggestions(count: Int) -> [Trigger]
    /// Çakışma varsa kimin kullandığını anlatan kısa Türkçe metin; boştaysa nil.
    func conflict(for trigger: Trigger) -> String?
    /// "⌃⌥⌘V", "Fare tuşu 4", "Üç parmakla çift dokunma".
    func displayString(for trigger: Trigger) -> String
    /// Kısayol kaydedilirken tetikleyicileri geçici olarak durdurur.
    func setSuspended(_ suspended: Bool)
    /// Sıradaki fare tuşu basımını yakalar (kayıt için). Zaman aşımında nil.
    func captureNextMouseButton() async -> Int?

    var accessibilityGranted: Bool { get }
    func requestAccessibility()
    /// Yalnızca ön koşul: bileşen yüklendi ve bir dokunmatik yüzey var. False ise seçenek hiç gösterilmez.
    var trackpadGestureAvailable: Bool { get }
    /// Canlı test: kullanıcı süre içinde üç parmakla çift dokunursa true.
    /// Dokunmatik yüzey tetikleyicisi yalnızca bu test geçerse eklenir.
    func testTrackpadGesture(timeout: TimeInterval) async -> Bool
}
