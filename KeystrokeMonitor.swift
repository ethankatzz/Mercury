import Foundation
import CoreGraphics

private func eventTapCallback(proxy: CGEventTapProxy, type: CGEventType,
                              event: CGEvent, userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else { return Unmanaged.passUnretained(event) }
    let m = Unmanaged<KeystrokeMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        if let tap = m.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
    case .keyDown:
        m.handle(event)
    default: break
    }
    return Unmanaged.passUnretained(event)
}

final class KeystrokeMonitor {
    private let stats: StatsEngine
    fileprivate var eventTap: CFMachPort?
    private var source: CFRunLoopSource?
    private var loop: CFRunLoop?
    private var thread: Thread?
    private(set) var isRunning = false

    init(stats: StatsEngine) { self.stats = stats }

    func hasPermission() -> Bool { CGPreflightListenEventAccess() }
    @discardableResult func requestPermission() -> Bool { CGRequestListenEventAccess() }

    @discardableResult
    func start() -> Bool {
        guard !isRunning else { return true }
        guard hasPermission() else { return false }
        let mask = CGEventMask(1) << CGEventMask(CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .listenOnly, eventsOfInterest: mask,
                                          callback: eventTapCallback, userInfo: refcon) else { return false }
        eventTap = tap; isRunning = true
        let t = Thread { [weak self] in self?.serviceLoop() }
        t.name = "mercury.tap"; t.stackSize = 512 * 1024; thread = t; t.start()
        return true
    }

    private func serviceLoop() {
        guard let tap = eventTap else { return }
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        source = src; let rl = CFRunLoopGetCurrent(); loop = rl
        CFRunLoopAddSource(rl, src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        CFRunLoopRun()
        if let s = source { CFRunLoopRemoveSource(rl, s, .commonModes) }
        CGEvent.tapEnable(tap: tap, enable: false)
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        if let rl = loop { CFRunLoopStop(rl) }
        loop = nil; thread = nil; eventTap = nil
    }

    fileprivate func handle(_ event: CGEvent) {
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return }
        let flags = event.flags
        if flags.contains(.maskCommand) || flags.contains(.maskControl) { return }
        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        if keycode == 51 || keycode == 117 { stats.recordBackspace(); return }
        var len = 0
        var chars = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &len, unicodeString: &chars)
        guard len > 0 else { return }
        let c = chars[0]
        if c == 9 || c == 10 || c == 13 { stats.recordCharacter(); return }
        if c < 0x20 || c == 0x7F { return }
        stats.recordCharacter()
    }
}
