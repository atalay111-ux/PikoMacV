// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "PikoMacV",
    defaultLocalization: "tr",
    platforms: [.macOS(.v14)],
    targets: [
        // Ortak modeller ve sözleşmeler. Diğer tüm hedefler yalnızca buna bağımlıdır.
        .target(name: "PikoMacVKit"),
        // PikoMacV izleme, geçmiş, dosya deposu, gizli sabitler, yapıştırma.
        .target(name: "PikoMacVCore", dependencies: ["PikoMacVKit"]),
        // Kısayollar, fare tuşu, dokunmatik yüzey tetikleyicileri, çakışma taraması.
        .target(name: "PikoMacVInput", dependencies: ["PikoMacVKit"]),
        // Panel, ayarlar, kurulum sihirbazı.
        .target(name: "PikoMacVUI", dependencies: ["PikoMacVKit"]),
        .executableTarget(name: "PikoMacV", dependencies: ["PikoMacVKit", "PikoMacVCore", "PikoMacVInput", "PikoMacVUI"]),
        // Donanım gerektirmeyen mantık testleri: `swift run PikoMacVSelfTest`
        .executableTarget(name: "PikoMacVSelfTest", dependencies: ["PikoMacVKit", "PikoMacVCore", "PikoMacVInput"]),
    ],
    swiftLanguageVersions: [.v5]
)
