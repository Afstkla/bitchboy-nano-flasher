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

final class ComboRecorder: ObservableObject {
    @Published var recording = false
    private var monitor: Any?

    func start(onCapture: @escaping ([Bool], String) -> Void) {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.recording else { return event }

            let label: String
            if let named = keyCodeLabels[event.keyCode] {
                label = named
            } else if let ch = event.charactersIgnoringModifiers?.lowercased(),
                      ch.count == 1, keyOptions.contains(where: { $0.label == ch }) {
                label = ch
            } else {
                return nil                       // swallow unmappable keys while recording
            }

            let flags = event.modifierFlags
            let mods = [flags.contains(.control), flags.contains(.option),
                        flags.contains(.shift), flags.contains(.command)]
            onCapture(mods, label)
            self.stop()
            return nil
        }
    }

    func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
