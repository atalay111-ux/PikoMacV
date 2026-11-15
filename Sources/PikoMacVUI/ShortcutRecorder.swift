import AppKit
import SwiftUI
import PikoMacVKit

@MainActor
final class RecorderModel: ObservableObject {
    @Published var recording = false
    private var monitor: Any?
    private weak var input: InputActions?

    private static let fKeys: Set<UInt16> = [105, 107, 113, 106, 64, 79, 80] // F13–F19

    func start(input: InputActions, onCapture: @escaping (Trigger) -> Void) {
        stop()
        self.input = input
        recording = true
        input.setSuspended(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            MainActor.assumeIsolated {
                guard let self else { return e }
                if e.keyCode == 53 { self.stop(); return nil }
                let mask = Fmt.carbonMask(e.modifierFlags.intersection(.deviceIndependentFlagsMask))
                if mask == 0 && !Self.fKeys.contains(e.keyCode) { NSSound.beep(); return nil }
                let trigger = Trigger.keyboard(keyCode: UInt32(e.keyCode), modifiers: mask)
                self.stop()
                onCapture(trigger)
                return nil
            }
        }
    }

    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        if recording {
            recording = false
            input?.setSuspended(false)
        }
    }
}

struct ShortcutRecorderButton: View {
    let input: InputActions
    var title = "Klavye kısayolu ekle"
    let onCapture: (Trigger) -> Void
    @StateObject private var recorder = RecorderModel()

    var body: some View {
        Button {
            if recorder.recording { recorder.stop() }
            else { recorder.start(input: input, onCapture: onCapture) }
        } label: {
            Label(recorder.recording ? "Tuşlara basın… (Esc iptal)" : title,
                  systemImage: recorder.recording ? "keyboard.badge.ellipsis" : "keyboard")
        }
        .onDisappear { recorder.stop() }
    }
}

/// Dokunmatik yüzey testi durumu (pencere oturumu boyunca paylaşılır).
@MainActor
final class TrackpadTestState: ObservableObject {
    enum Phase { case idle, testing, success, failed }
    @Published var phase: Phase = .idle
    @Published var failures = 0
    var hidden: Bool { failures >= 2 }
}

/// Bir kipin tetikleyicilerini listeler ve eklemeye izin verir (Ayarlar ve kurulum sihirbazı ortak kullanır).
struct TriggerEditor: View {
    let mode: PanelMode
    @SwiftUI.Binding var bindings: [PikoMacVBinding]
    let input: InputActions
    var failures: [UUID: String] = [:]
    var suggestions: [Trigger] = []
    @ObservedObject var trackpad: TrackpadTestState
    var onChange: () -> Void = {}

    @Local private var capturingMouse = false
    @Local private var message: String?
    @Local private var testToken = 0

    private var mine: [PikoMacVBinding] { bindings.filter { $0.mode == mode } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !suggestions.isEmpty {
                Text("Önerilen boş kısayollar").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(suggestions, id: \.self) { t in
                        let on = mine.contains { $0.trigger == t }
                        Button { toggle(t) } label: {
                            Text(input.displayString(for: t))
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(Capsule().fill(on ? Color.accentColor : Color.primary.opacity(0.1)))
                                .foregroundStyle(on ? Color.white : Color.primary)
                        }.buttonStyle(.plain)
                    }
                }
            }
            if mine.isEmpty {
                Text("Henüz tetikleyici yok").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(mine) { b in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(input.displayString(for: b.trigger))
                            .font(.system(.body, design: .rounded).weight(.medium))
                            .padding(.horizontal, 10).padding(.vertical, 3)
                            .background(Capsule().fill(Color.primary.opacity(0.1)))
                        Spacer()
                        Button { remove(b.id) } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(.secondary).help("Kaldır")
                    }
                    if let w = warning(for: b) {
                        Label(w, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            HStack {
                ShortcutRecorderButton(input: input) { add($0) }
                Button {
                    capturingMouse = true
                    Task { @MainActor in
                        let n = await input.captureNextMouseButton()
                        capturingMouse = false
                        if let n { add(.mouseButton(n)) }
                    }
                } label: {
                    Label(capturingMouse ? "Fare tuşuna basın…" : "Fare tuşu ekle", systemImage: "computermouse")
                }.disabled(capturingMouse)
            }
            if input.trackpadGestureAvailable && !trackpad.hidden { trackpadSection }
            if let message {
                Label(message, systemImage: "info.circle").font(.caption).foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var trackpadSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch trackpad.phase {
            case .testing:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Şimdi dokunmatik yüzeye üç parmakla çift dokunun…")
                    Button("İptal") { cancelTest() }
                }
            case .success:
                Label("Hareket algılandı", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .failed:
                Label("Hareket algılanamadı. Bu Mac'te bu özellik desteklenmiyor olabilir.",
                      systemImage: "xmark.circle").font(.caption).foregroundStyle(.orange)
                Button("Tekrar dene") { runTest() }
            case .idle:
                EmptyView()
            }
            if trackpad.phase != .testing {
                Button { runTest() } label: {
                    Label("Dokunmatik yüzey hareketi ekle", systemImage: "hand.tap")
                }
            }
        }
    }

    private func runTest() {
        trackpad.phase = .testing
        testToken += 1
        let token = testToken
        Task { @MainActor in
            let ok = await input.testTrackpadGesture(timeout: 10)
            guard token == testToken, trackpad.phase == .testing else { return }
            if ok {
                trackpad.failures = 0
                trackpad.phase = .success
                add(.trackpadThreeFingerDoubleTap)
            } else {
                trackpad.failures += 1
                trackpad.phase = .failed
            }
        }
    }

    private func cancelTest() {
        testToken += 1
        trackpad.phase = .idle
    }

    private func warning(for b: PikoMacVBinding) -> String? {
        if let f = failures[b.id] { return f }
        return input.conflict(for: b.trigger)
    }

    private func toggle(_ t: Trigger) {
        if let b = mine.first(where: { $0.trigger == t }) { remove(b.id) } else { add(t) }
    }

    private func add(_ t: Trigger) {
        message = nil
        if t == .trackpadThreeFingerDoubleTap {
            bindings.removeAll { $0.trigger == t && $0.mode != mode }
        }
        if bindings.contains(where: { $0.trigger == t && $0.mode != mode }) {
            message = "Bu tetikleyici diğer kip için kullanılıyor; her kip için farklı olmalı."
            return
        }
        if mine.contains(where: { $0.trigger == t }) { return }
        bindings.append(PikoMacVBinding(mode: mode, trigger: t))
        onChange()
    }

    private func remove(_ id: UUID) {
        bindings.removeAll { $0.id == id }
        onChange()
    }
}
