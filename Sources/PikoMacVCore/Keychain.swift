import Foundation

/// Gizli sabitlerin Anahtar Zinciri deposu.
///
/// Öğeler doğrudan Security API'siyle değil, macOS'in kendi `/usr/bin/security` aracı üzerinden yazılıp okunur.
/// Neden: Apple ekip kimliği olmayan (kendinden imzalı) uygulamalarda anahtar zinciri öğeleri uygulamanın
/// o anki ikili özetine bağlanır; uygulama güncellenince öğeler okunamaz hâle gelir. Apple'ın aracı üzerinden
/// oluşturulan öğeler bundan etkilenmez. İçerik oturum anahtar zincirinde şifreli durur.
/// Değer, komut satırında görünmemesi için aracın standart girdisinden ve onaltılık kodlanmış olarak verilir.
enum SecretStore {
    /// PIKOMACV_DATA_DIR (demo/ekran görüntüsü) verilmişse gerçek sabitlerle karışmasın diye ayrı servis adı.
    static let isDemo: Bool = (ProcessInfo.processInfo.environment["PIKOMACV_DATA_DIR"] ?? "").isEmpty == false
    static let service = isDemo ? "com.pikomacv.secrets.demo" : "com.pikomacv.secrets"
    private static let tool = "/usr/bin/security"

    @discardableResult
    private static func run(arguments: [String], stdin: String? = nil) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = arguments
        let out = Pipe(), input = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        if stdin != nil { p.standardInput = input }
        do { try p.run() } catch { return (-1, "") }
        if let stdin {
            input.fileHandleForWriting.write(Data(stdin.utf8))
            try? input.fileHandleForWriting.close()
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    private static func hex(_ s: String) -> String { Data(s.utf8).map { String(format: "%02x", $0) }.joined() }

    private static func unhex(_ s: String) -> String? {
        let chars = Array(s)
        guard chars.count % 2 == 0 else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(chars.count / 2)
        for i in stride(from: 0, to: chars.count, by: 2) {
            guard let b = UInt8(String(chars[i...i + 1]), radix: 16) else { return nil }
            bytes.append(b)
        }
        return String(data: Data(bytes), encoding: .utf8)
    }

    /// Hesap adı yalnızca UUID olabilir; komut satırına başka bir şey sızmasın.
    private static func valid(_ account: String) -> Bool { UUID(uuidString: account) != nil }

    @discardableResult
    static func set(_ value: String, account: String) -> Bool {
        guard valid(account) else { return false }
        // -U: varsa güncelle, -A: uygulama güncellense de sormadan okunabilsin.
        let command = "add-generic-password -U -A -s \(service) -a \(account) -l \"PikoMacV gizli sabit\" -w \(hex(value))\n"
        return run(arguments: ["-i"], stdin: command).status == 0 && get(account: account) == value
    }

    static func get(account: String) -> String? {
        guard valid(account) else { return nil }
        var r = run(arguments: ["find-generic-password", "-s", service, "-a", account, "-w"])
        // Ad değişikliğinden önce oluşturulan sabitler eski servis adında durur.
        if r.status != 0 && !isDemo { r = run(arguments: ["find-generic-password", "-s", "com.macv.secrets", "-a", account, "-w"]) }
        guard r.status == 0 else { return nil }
        return unhex(r.output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func delete(account: String) {
        guard valid(account) else { return }
        run(arguments: ["delete-generic-password", "-s", service, "-a", account])
    }
}
