import AppKit

// macOS virtual keyCodes for keys whose characters aren't usable directly.
private let keyCodeLabels: [UInt16: String] = [
    36: "Enter", 48: "Tab", 49: "Space", 51: "Backspace", 53: "Escape",
    117: "Delete", 115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
    126: "Up", 125: "Down", 123: "Left", 124: "Right",
    122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
    98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18",
    80: "F19", 90: "F20",
]

// Pauses shorter than this are just typing rhythm; longer ones are the user
// deliberately waiting for something, so they become Wait steps.
private let deliberatePauseMs = 400.0

private func heldModifiers(_ event: NSEvent) -> [Bool] {
    let flags = event.modifierFlags
    return [flags.contains(.control), flags.contains(.option),
            flags.contains(.shift), flags.contains(.command)]
}

private func keyLabel(for event: NSEvent) -> String? {
    if let named = keyCodeLabels[event.keyCode] { return named }
    guard let ch = event.charactersIgnoringModifiers?.lowercased(), ch.count == 1,
          keyOptions.contains(where: { $0.label == ch })
    else { return nil }
    return ch
}

final class ComboRecorder: ObservableObject {
    @Published var recording = false
    private var monitor: Any?
    private var emit: ((MacroStep) -> Void)?
    private var pendingText = ""
    private var lastEventAt: TimeInterval = 0

    func start(onCapture: @escaping ([Bool], String) -> Void) {
        listen { [weak self] event in
            guard let label = keyLabel(for: event) else { return }
            onCapture(heldModifiers(event), label)
            self?.stop()
        }
    }

    // Plain typing collects into one Text step, anything with a modifier becomes a
    // Combo step, and a deliberate pause between them becomes a Wait.
    func startMacro(onStep: @escaping (MacroStep) -> Void) {
        emit = onStep
        pendingText = ""
        lastEventAt = 0
        listen { [weak self] event in self?.record(event) }
    }

    func stop() {
        flushText()
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        emit = nil
    }

    private func listen(_ handle: @escaping (NSEvent) -> Void) {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.recording else { return event }
            handle(event)
            return nil                       // swallow everything while recording
        }
    }

    private func record(_ event: NSEvent) {
        let now = ProcessInfo.processInfo.systemUptime
        let gapMs = lastEventAt == 0 ? 0 : (now - lastEventAt) * 1000
        lastEventAt = now

        let mods = heldModifiers(event)
        let typing = !(mods[0] || mods[1] || mods[3])

        if typing && !pendingText.isEmpty {
            if event.keyCode == 51 { pendingText.removeLast(); return }
            if event.keyCode == 36 { pendingText += "\n"; return }
        }

        if typing, let ch = event.characters, ch.count == 1,
           let scalar = ch.unicodeScalars.first, scalar.value >= 32, scalar.value < 127 {
            pause(gapMs)
            pendingText += ch
            return
        }

        pause(gapMs)
        guard let label = keyLabel(for: event) else { return }
        emit?(MacroStep(kind: .tap, mods: mods, keyLabel: label))
    }

    private func pause(_ gapMs: Double) {
        guard gapMs >= deliberatePauseMs else { return }
        flushText()
        emit?(MacroStep(kind: .wait, waitMs: min((gapMs / 50).rounded() * 50, 5000)))
    }

    private func flushText() {
        guard !pendingText.isEmpty else { return }
        emit?(MacroStep(kind: .text, text: pendingText))
        pendingText = ""
    }

}
