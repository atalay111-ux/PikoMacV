import Foundation

// MultitouchSupport.framework (özel API) — çalışma anında dlopen ile yüklenir; bağlantı zamanı bağımlılığı yok.

private typealias MTContactCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32
private typealias MTCreateListFn = @convention(c) () -> Unmanaged<CFArray>?
private typealias MTRegisterFn = @convention(c) (UnsafeMutableRawPointer, MTContactCallback) -> Void
private typealias MTStartFn = @convention(c) (UnsafeMutableRawPointer, Int32) -> Void
private typealias MTStopFn = @convention(c) (UnsafeMutableRawPointer) -> Void

/// Bilinen MTTouch düzeni (96 bayt): frame@0 Int32, timestamp@8 Double, identifier@16, state@20,
/// fingerID@24, handID@28, normalized.position.x@32 y@36 (Float), ...
private let mtTouchStride = 96
private let mtOffTimestamp = 8
private let mtOffIdentifier = 16
private let mtOffState = 20
private let mtOffPosX = 32
private let mtOffPosY = 36

/// Arka plan iş parçacığında çalışan çift dokunma algılayıcı.
/// Durum aygıt başına tutulur: başka bir aygıtın (ör. Magic Mouse) kareleri dokunuşu bozmasın.
final class TapDetector: @unchecked Sendable {
    private struct DeviceState {
        var candidateStart: Double?
        var candidateValid = false
        var maxCount = 0
        var startPos: [Int32: (Float, Float)] = [:]
        var lastTap: Double?
    }

    // Toleranslar: tek dokunuşun en uzun süresi, iki dokunuş arası süre, izin verilen kayma.
    private let maxTapDuration = 0.35
    private let maxTapGap = 0.55
    private let maxDrift: Float = 0.08

    private let lock = NSLock()
    private var states: [UInt: DeviceState] = [:]
    private var frames = 0
    private var diag: [String] = []
    private var maxContacts = 0
    var onDoubleTap: (@Sendable () -> Void)?

    /// Son sıfırlamadan beri gelen kare sayısı (tanılama için).
    var framesSeen: Int { lock.lock(); defer { lock.unlock() }; return frames }
    /// Test tanılaması: kare sayısı, en çok parmak ve her dokunuşun neden kabul/ret edildiği.
    var diagnostics: String {
        lock.lock(); defer { lock.unlock() }
        return "kare=\(frames) enCokParmak=\(maxContacts)\n" + diag.suffix(30).joined(separator: "\n")
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        states = [:]; frames = 0; diag = []; maxContacts = 0
    }

    func process(device: UnsafeMutableRawPointer?, touches: UnsafeMutableRawPointer?, count: Int, time: Double) {
        // Yalnızca temas halindeki parmaklar (state 2 = başlıyor, 3 = yaklaşıyor, 4 = dokunuyor).
        var active: [(id: Int32, x: Float, y: Float)] = []
        if let touches, count > 0 {
            for i in 0..<count {
                let base = touches + i * mtTouchStride
                let state = base.load(fromByteOffset: mtOffState, as: Int32.self)
                guard state >= 2 && state <= 4 else { continue }
                let id = base.load(fromByteOffset: mtOffIdentifier, as: Int32.self)
                let x = base.loadUnaligned(fromByteOffset: mtOffPosX, as: Float.self)
                let y = base.loadUnaligned(fromByteOffset: mtOffPosY, as: Float.self)
                active.append((id, x, y))
            }
        }
        let key = UInt(bitPattern: device)
        var fire = false
        lock.lock()
        frames += 1
        var st = states[key] ?? DeviceState()
        maxContacts = max(maxContacts, active.count)
        if active.isEmpty {
            if let start = st.candidateStart {
                diag.append(String(format: "dokunus sure=%.3f parmak=%d gecerli=%d oncekiAra=%.3f", time - start, st.maxCount, st.candidateValid ? 1 : 0, st.lastTap.map { time - $0 } ?? -1))
                if st.candidateValid, st.maxCount == 3, time - start < maxTapDuration {
                    if let prev = st.lastTap, start - prev < maxTapGap { fire = true; st.lastTap = nil } else { st.lastTap = time }
                } else {
                    // Geçersiz dokunuş seriyi bozar.
                    st.lastTap = nil
                }
            }
            st.candidateStart = nil; st.candidateValid = false; st.maxCount = 0; st.startPos = [:]
        } else {
            if st.candidateStart == nil {
                st.candidateStart = time; st.candidateValid = true; st.maxCount = 0; st.startPos = [:]
            }
            st.maxCount = max(st.maxCount, active.count)
            if st.maxCount > 3 { st.candidateValid = false }
            if let start = st.candidateStart, time - start > maxTapDuration { st.candidateValid = false }
            for t in active {
                if let s = st.startPos[t.id] {
                    if abs(t.x - s.0) > maxDrift || abs(t.y - s.1) > maxDrift { st.candidateValid = false }
                } else {
                    st.startPos[t.id] = (t.x, t.y)
                }
            }
        }
        states[key] = st
        lock.unlock()
        if fire { onDoubleTap?() }
    }
}

private let sharedDetector = TapDetector()

private let mtCallback: MTContactCallback = { device, touches, count, timestamp, _ in
    sharedDetector.process(device: device, touches: touches, count: Int(count), time: timestamp)
    return 0
}

final class MultitouchMonitor {
    private var handle: UnsafeMutableRawPointer?
    private var createList: MTCreateListFn?
    private var register: MTRegisterFn?
    private var unregister: MTRegisterFn?
    private var start: MTStartFn?
    private var stop: MTStopFn?
    private var devices: CFArray?
    private var running = false

    init() {
        handle = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW)
        guard let h = handle else { return }
        func sym<T>(_ name: String, _ type: T.Type) -> T? {
            guard let p = dlsym(h, name) else { return nil }
            return unsafeBitCast(p, to: type)
        }
        createList = sym("MTDeviceCreateList", MTCreateListFn.self)
        register = sym("MTRegisterContactFrameCallback", MTRegisterFn.self)
        unregister = sym("MTUnregisterContactFrameCallback", MTRegisterFn.self)
        start = sym("MTDeviceStart", MTStartFn.self)
        stop = sym("MTDeviceStop", MTStopFn.self)
    }

    private var symbolsOK: Bool { createList != nil && register != nil && unregister != nil && start != nil && stop != nil }

    private func deviceList() -> CFArray? {
        guard symbolsOK, let list = createList?()?.takeRetainedValue() else { return nil }
        return CFArrayGetCount(list) > 0 ? list : nil
    }

    var available: Bool { running || deviceList() != nil }

    func startMonitoring(onDoubleTap: @escaping @Sendable () -> Void) -> Bool {
        stopMonitoring()
        guard let list = deviceList(), let register, let start else { return false }
        sharedDetector.reset()
        sharedDetector.onDoubleTap = onDoubleTap
        for i in 0..<CFArrayGetCount(list) {
            guard let p = CFArrayGetValueAtIndex(list, i) else { continue }
            let dev = UnsafeMutableRawPointer(mutating: p)
            register(dev, mtCallback)
            start(dev, 0)
        }
        devices = list
        running = true
        return true
    }

    /// Son başlatmadan beri aygıtlardan gelen kare sayısı.
    var framesSeen: Int { sharedDetector.framesSeen }
    var diagnostics: String { sharedDetector.diagnostics }

    func stopMonitoring() {
        guard running, let list = devices, let unregister, let stop else { running = false; return }
        for i in 0..<CFArrayGetCount(list) {
            guard let p = CFArrayGetValueAtIndex(list, i) else { continue }
            let dev = UnsafeMutableRawPointer(mutating: p)
            unregister(dev, mtCallback)
            stop(dev)
        }
        sharedDetector.onDoubleTap = nil
        devices = nil
        running = false
    }
}
