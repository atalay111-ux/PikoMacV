import CoreGraphics
import Foundation
import PikoMacVKit

/// Event tap geri çağrısı ile ana iş parçacığı arasındaki paylaşılan durum.
final class MouseShared: @unchecked Sendable {
    private let lock = NSLock()
    private var map: [Int: PanelMode] = [:]
    var port: CFMachPort?
    var onFire: (@Sendable (PanelMode) -> Void)?

    func setButtons(_ m: [Int: PanelMode]) { lock.lock(); map = m; lock.unlock() }
    func mode(for button: Int) -> PanelMode? { lock.lock(); defer { lock.unlock() }; return map[button] }
}

let mouseShared = MouseShared()

private let mouseTapCallback: CGEventTapCallBack = { _, type, event, _ in
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let port = mouseShared.port { CGEvent.tapEnable(tap: port, enable: true) }
        return Unmanaged.passUnretained(event)
    }
    guard type == .otherMouseDown || type == .otherMouseUp else { return Unmanaged.passUnretained(event) }
    let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
    guard let mode = mouseShared.mode(for: button) else { return Unmanaged.passUnretained(event) }
    if type == .otherMouseDown { mouseShared.onFire?(mode) }
    return nil // down ve up yutulur
}

final class MouseTap {
    private var source: CFRunLoopSource?

    var isActive: Bool { mouseShared.port != nil }

    func start() -> Bool {
        if isActive { return true }
        let mask = (1 << CGEventType.otherMouseDown.rawValue) | (1 << CGEventType.otherMouseUp.rawValue)
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: CGEventMask(mask), callback: mouseTapCallback, userInfo: nil) else { return false }
        mouseShared.port = port
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }

    func stop() {
        if let port = mouseShared.port { CGEvent.tapEnable(tap: port, enable: false); CFMachPortInvalidate(port) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil
        mouseShared.port = nil
        mouseShared.setButtons([:])
    }
}
