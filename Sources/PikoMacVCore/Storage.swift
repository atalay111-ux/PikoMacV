import CryptoKit
import Foundation
import PikoMacVKit

/// Disk yerleşimi: ~/Library/Application Support/PikoMacV/
struct StoragePaths {
    let root: URL
    var history: URL { root.appendingPathComponent("history.json") }
    var pins: URL { root.appendingPathComponent("pins.json") }
    var settings: URL { root.appendingPathComponent("settings.json") }
    var blobs: URL { root.appendingPathComponent("blobs", isDirectory: true) }
    var vault: URL { root.appendingPathComponent("vault", isDirectory: true) }
    var cache: URL {
        if let dir = ProcessInfo.processInfo.environment["PIKOMACV_DATA_DIR"], !dir.isEmpty {
            return root.appendingPathComponent("cache", isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/PikoMacV", isDirectory: true)
    }

    init() {
        // Tanılama/ekran görüntüsü: PIKOMACV_DATA_DIR verilirse tüm veri orada durur (gerçek veriye dokunulmaz).
        if let dir = ProcessInfo.processInfo.environment["PIKOMACV_DATA_DIR"], !dir.isEmpty {
            root = URL(fileURLWithPath: (dir as NSString).expandingTildeInPath, isDirectory: true)
            return
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        root = base.appendingPathComponent("PikoMacV", isDirectory: true)
    }

    func prepare() {
        let fm = FileManager.default
        for dir in [root, blobs, vault, cache] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    func blobURL(_ name: String) -> URL { blobs.appendingPathComponent(name) }
    func vaultURL(_ stored: String) -> URL { vault.appendingPathComponent(stored) }
}

enum Hashing {
    static func hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    static func hex(_ string: String) -> String { hex(Data(string.utf8)) }
}

enum JSONStore {
    static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(type, from: data)
    }

    static func encode<T: Encodable>(_ value: T) -> Data? {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        return try? enc.encode(value)
    }
}
