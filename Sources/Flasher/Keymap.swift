import Foundation

enum KeyKind { case kbd, con }

struct KeyOption: Hashable {
    let label: String
    let kind: KeyKind
    let code: UInt16
    let legend: String
}

struct Modifier {
    let symbol: String
    let name: String
}

// Order is the bit order of the mods mask in the keymap blob, and matches MOD_KEYS
// in keypad.c.
let modifiers: [Modifier] = [
    Modifier(symbol: "⌃", name: "control"),
    Modifier(symbol: "⌥", name: "option"),
    Modifier(symbol: "⇧", name: "shift"),
    Modifier(symbol: "⌘", name: "command"),
]

func modMask(_ mods: [Bool]) -> UInt8 {
    mods.enumerated().reduce(0) { $1.element ? $0 | UInt8(1 << $1.offset) : $0 }
}

// Keycodes as usb_conkbd.h defines them: printable ASCII passes through, everything
// else has a code above 0x7f that KBD_press maps to a HID usage.
let keyOptions: [KeyOption] = {
    var opts: [KeyOption] = []
    for ch in "abcdefghijklmnopqrstuvwxyz0123456789" {
        opts.append(KeyOption(label: String(ch), kind: .kbd,
                              code: UInt16(ch.asciiValue!),
                              legend: String(ch).uppercased()))
    }
    let specials: [(String, UInt16, String)] = [
        ("Space", 0x20, "␣"), ("Enter", 0xB0, "⏎"),
        ("Escape", 0xB1, "⎋"), ("Tab", 0xB3, "⇥"),
        ("Backspace", 0xB2, "⌫"), ("Delete", 0xD4, "⌦"),
        ("Up", 0xDA, "↑"), ("Down", 0xD9, "↓"),
        ("Left", 0xD8, "←"), ("Right", 0xD7, "→"),
        ("Home", 0xD2, "↖"), ("End", 0xD5, "↘"),
        ("Page Up", 0xD3, "⇞"), ("Page Down", 0xD6, "⇟"),
    ]
    for (label, code, legend) in specials {
        opts.append(KeyOption(label: label, kind: .kbd, code: code, legend: legend))
    }
    for n in 1...24 {
        let code: UInt16 = n <= 12 ? 0xC2 + UInt16(n - 1) : 0xF0 + UInt16(n - 13)
        opts.append(KeyOption(label: "F\(n)", kind: .kbd, code: code, legend: "F\(n)"))
    }
    let media: [(String, UInt16, String)] = [
        ("Play/Pause", 0xCD, "⏯"), ("Next Track", 0xB5, "⏭"),
        ("Previous Track", 0xB6, "⏮"), ("Volume Up", 0xE9, "VOL+"),
        ("Volume Down", 0xEA, "VOL−"), ("Mute", 0xE2, "MUTE"),
    ]
    for (label, code, legend) in media {
        opts.append(KeyOption(label: label, kind: .con, code: code, legend: legend))
    }
    return opts
}()

func keyOption(_ label: String) -> KeyOption {
    keyOptions.first { $0.label == label } ?? keyOptions[0]
}

// The pads ship an RGB die per key but only wire green and blue; sweeping every pin
// pair and both rails on all ten GPIOs never lit red. See README.
enum LedMode: String, CaseIterable, Codable {
    case off, solid, breathe, cycle

    // Matches LED_MODE_* in config.h.
    var code: UInt8 {
        switch self {
        case .off: return 0
        case .solid: return 1
        case .breathe: return 2
        case .cycle: return 3
        }
    }

    var label: String {
        switch self {
        case .off: return "Off"
        case .solid: return "Solid"
        case .breathe: return "Breathe"
        case .cycle: return "Cycle"
        }
    }

    var usesColour: Bool { self == .solid || self == .breathe }
    var usesPeriod: Bool { self == .breathe || self == .cycle }
}

struct LedSpec: Codable {
    var mode: LedMode = .off
    var green: Double = 0
    var blue: Double = 1
    var periodMs: Double = 2000
    var lightWhilePressed: Bool = true
    var pressGreen: Double = 1
    var pressBlue: Double = 1

    var legend: String {
        if mode == .off && !lightWhilePressed { return "dark" }
        return mode == .off ? "on press" : mode.label.lowercased()
    }
}

func level(_ fraction: Double) -> Int {
    Int((min(max(fraction, 0), 1) * 255).rounded())
}

enum KeySpecMode: String, Codable, CaseIterable {
    case key, text, macro

    var label: String {
        switch self {
        case .key: return "Key combo"
        case .text: return "Type text"
        case .macro: return "Macro"
        }
    }
}

enum StepKind: String, Codable, CaseIterable {
    case tap, text, wait

    var label: String {
        switch self {
        case .tap: return "Combo"
        case .text: return "Text"
        case .wait: return "Wait"
        }
    }
}

struct MacroStep: Codable {
    var kind: StepKind = .tap
    var mods: [Bool] = [false, false, false, false]
    var keyLabel: String = "a"
    var text: String = ""
    var waitMs: Double = 100
}

struct KeySpec: Codable {
    var mode: KeySpecMode = .key
    var mods: [Bool] = [false, false, false, false]
    var keyLabel: String = "a"
    var text: String = ""
    var led = LedSpec()

    // Absent from keymap.json files written before macros existed, and a synthesised
    // decoder rejects a missing key even when the property has a default.
    var macroSteps: [MacroStep]?
    var steps: [MacroStep] {
        get { macroSteps ?? [] }
        set { macroSteps = newValue }
    }

    var legend: String {
        if mode == .macro { return "▶\(steps.count)" }
        if mode == .text {
            let flat = text.replacingOccurrences(of: "\n", with: "⏎")
            if flat.isEmpty { return "…" }
            return "“" + flat.prefix(7) + (flat.count > 7 ? "…”" : "”")
        }
        let opt = keyOption(keyLabel)
        let prefix = opt.kind == .con ? "" :
            zip(modifiers, mods).filter { $0.1 }.map { $0.0.symbol }.joined()
        return prefix + opt.legend
    }
}

struct KeymapError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// macOS smart-substitutes typographic characters while typing; fold the common
// ones back to ASCII instead of rejecting them.
private let asciiFolds: [Character: String] = [
    "\u{2019}": "'", "\u{2018}": "'", "\u{201A}": "'",
    "\u{201C}": "\"", "\u{201D}": "\"", "\u{201E}": "\"",
    "\u{2013}": "-", "\u{2014}": "-", "\u{2212}": "-",
    "\u{2026}": "...", "\u{00A0}": " ",
]

func asciiBytes(_ text: String) throws -> [UInt8] {
    let folded = text.map { asciiFolds[$0] ?? String($0) }.joined()
    return try folded.unicodeScalars.map { ch in
        switch ch {
        case "\n", "\t": return UInt8(ch.value)
        case let c where c.value >= 32 && c.value < 127: return UInt8(c.value)
        default: throw KeymapError(message: "only plain ASCII can be typed, not '\(ch)'")
        }
    }
}

// The blob the flasher patches into the compiled firmware. Layout and step encoding
// are documented at the top of firmware/keypad.c - keep the two in step, and bump the
// version byte in the magic if they ever diverge.
let blobMagic: [UInt8] = Array("BBNKMAP".utf8) + [1]
let blobSize = 512

private let stepTap: UInt8 = 0, stepTapCon: UInt8 = 1, stepText: UInt8 = 2, stepWait: UInt8 = 3
private let actHoldKbd: UInt8 = 0, actHoldCon: UInt8 = 1, actSequence: UInt8 = 2

private func little(_ value: UInt16) -> [UInt8] { [UInt8(value & 0xff), UInt8(value >> 8)] }

private func ledBytes(_ led: LedSpec) -> [UInt8] {
    [led.mode.code, UInt8(level(led.green)), UInt8(level(led.blue))]
        + little(UInt16(min(max(led.periodMs, 0), 65535)))
        + [led.lightWhilePressed ? 1 : 0,
           UInt8(level(led.pressGreen)), UInt8(level(led.pressBlue))]
}

// One text step carries at most 255 bytes, so a long paste becomes several.
private func textSteps(_ text: String) throws -> [[UInt8]] {
    let bytes = try asciiBytes(text)
    return stride(from: 0, to: bytes.count, by: 255).map { start in
        let chunk = Array(bytes[start..<min(start + 255, bytes.count)])
        return [stepText, UInt8(chunk.count)] + chunk
    }
}

private func stepBytes(_ step: MacroStep) throws -> [[UInt8]] {
    switch step.kind {
    case .wait:
        return [[stepWait] + little(UInt16(min(max(step.waitMs, 0), 65535)))]
    case .text:
        return try textSteps(step.text)
    case .tap:
        let opt = keyOption(step.keyLabel)
        return opt.kind == .con
            ? [[stepTapCon] + little(opt.code)]
            : [[stepTap, modMask(step.mods), UInt8(opt.code)]]
    }
}

func actionBytes(_ spec: KeySpec) throws -> [UInt8] {
    if spec.mode == .key {
        let opt = keyOption(spec.keyLabel)
        return opt.kind == .con
            ? [actHoldCon] + little(opt.code)
            : [actHoldKbd, modMask(spec.mods), UInt8(opt.code)]
    }
    var steps: [[UInt8]] = []
    if spec.mode == .text {
        steps = try textSteps(spec.text)
    } else {
        for step in spec.steps { steps += try stepBytes(step) }
    }
    guard steps.count <= 255 else {
        throw KeymapError(message: "a macro can hold at most 255 steps")
    }
    return [actSequence, UInt8(steps.count)] + steps.flatMap { $0 }
}

func keymapBlob(_ spec1: KeySpec, _ spec2: KeySpec) throws -> [UInt8] {
    let action1 = try actionBytes(spec1)
    let action2 = try actionBytes(spec2)
    var blob = blobMagic + ledBytes(spec1.led) + ledBytes(spec2.led)
    blob += little(UInt16(26 + action1.count)) + action1 + action2
    guard blob.count <= blobSize else {
        throw KeymapError(message: "this keymap needs \(blob.count) bytes and the "
                          + "firmware reserves \(blobSize) - shorten a macro")
    }
    return blob + [UInt8](repeating: 0, count: blobSize - blob.count)
}

func patchedFirmware(_ image: [UInt8], with blob: [UInt8]) throws -> [UInt8] {
    let hits = (0...(max(image.count - blobMagic.count, 0)))
        .filter { Array(image[$0..<($0 + blobMagic.count)]) == blobMagic }
    guard hits.count == 1, let at = hits.first, at + blobSize <= image.count else {
        throw KeymapError(message: hits.count > 1
            ? "the firmware image carries the keymap marker more than once"
            : "no keymap marker in the firmware image - rebuild with make -C firmware bin")
    }
    var patched = image
    patched.replaceSubrange(at..<(at + blobSize), with: blob)
    return patched
}

// The WCH bootloader cannot read flash back, so what is on the pad can never be
// queried - this sidecar is the closest thing to remembering it.
//
// ponytail: one file, so it tracks one pad. Name it per device if you ever want
// several with different keymaps.
func saveSpecs(_ specs: [KeySpec], to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(specs).write(to: url, options: .atomic)
}

func loadSpecs(from url: URL) -> [KeySpec]? {
    guard let data = try? Data(contentsOf: url),
          let specs = try? JSONDecoder().decode([KeySpec].self, from: data),
          specs.count == 2
    else { return nil }
    return specs
}

func runCheck() throws {
    var s1 = KeySpec()
    s1.mods = [true, false, false, true]
    s1.keyLabel = "F13"
    assert(try! actionBytes(s1) == [0, 0b1001, 0xF0])
    assert(s1.legend == "⌃⌘F13")

    var media = KeySpec()
    media.keyLabel = "Volume Up"
    assert(try! actionBytes(media) == [1, 0xE9, 0x00])

    var s2 = KeySpec(mode: .text)
    s2.text = "hi\nthere"
    assert(try! actionBytes(s2)
        == [2, 1, 2, 8, 104, 105, 10, 116, 104, 101, 114, 101])

    var mac = KeySpec(mode: .macro)
    mac.steps = [
        MacroStep(kind: .tap, mods: [false, false, false, true], keyLabel: "Space"),
        MacroStep(kind: .wait, waitMs: 300),
        MacroStep(kind: .text, text: "ok\n"),
        MacroStep(kind: .tap, keyLabel: "Volume Up"),
    ]
    assert(try! actionBytes(mac)
        == [2, 4, 0, 0b1000, 0x20, 3, 0x2C, 0x01, 2, 3, 111, 107, 10, 1, 0xE9, 0x00])
    assert(mac.legend == "▶4")

    var long = KeySpec(mode: .text)
    long.text = String(repeating: "x", count: 300)
    let split = try actionBytes(long)
    assert(split[1] == 2 && split[3] == 255 && split[259] == 2 && split[260] == 45)

    assert((try? asciiBytes("héllo")) == nil, "non-ASCII should be rejected")
    assert(try! asciiBytes("Hi, I\u{2019}m \u{201C}Nano\u{201D} \u{2014} ok\u{2026}")
        == Array("Hi, I'm \"Nano\" - ok...".utf8))

    var lit = KeySpec()
    lit.led = LedSpec(mode: .breathe, green: 1, blue: 0, periodMs: 1500,
                      lightWhilePressed: true, pressGreen: 0, pressBlue: 1)
    let blob = try keymapBlob(s1, lit)
    assert(blob.count == blobSize)
    assert(Array(blob[0..<8]) == blobMagic)
    assert(Array(blob[16..<24]) == [2, 255, 0, 0xDC, 0x05, 1, 0, 255])
    assert(Array(blob[24..<26]) == [29, 0])              // key 2 follows key 1's 3 bytes
    assert(Array(blob[26..<32]) == [0, 0b1001, 0xF0, 0, 0, 0x61])
    assert(level(0.5) == 128 && level(-1) == 0 && level(2) == 255)

    var huge = KeySpec(mode: .text)
    huge.text = String(repeating: "y", count: 600)
    assert((try? keymapBlob(huge, huge)) == nil, "an oversized keymap should be refused")

    let image = [UInt8](repeating: 0xAA, count: 100) + blobMagic
        + [UInt8](repeating: 0, count: blobSize)
    let patched = try patchedFirmware(image, with: blob)
    assert(patched.count == image.count)
    assert(Array(patched[0..<100]) == Array(image[0..<100]))
    assert(Array(patched[100..<(100 + blobSize)]) == blob)
    assert((try? patchedFirmware([UInt8](repeating: 0, count: 600), with: blob)) == nil)

    // The blob format is defined twice - here and in keypad.c - so check they agree.
    let firmwareSource = firmwareImage.deletingLastPathComponent()
        .appendingPathComponent("keypad.c")
    if let source = try? String(contentsOf: firmwareSource) {
        func constant(_ name: String) -> Int? {
            source.split(separator: "\n")
                .first { $0.split(separator: " ").dropFirst().first == Substring(name) }
                .flatMap { Int($0.split(separator: " ").last ?? "") }
        }
        assert(constant("BLOB_SIZE") == blobSize)
        assert(constant("KEY2_ACTION") == 24 && constant("KEY1_ACTION") == 26)
        assert(constant("ACT_HOLD_KBD") == Int(actHoldKbd)
               && constant("ACT_HOLD_CON") == Int(actHoldCon)
               && constant("ACT_SEQUENCE") == Int(actSequence))
        assert(constant("STEP_TAP") == Int(stepTap)
               && constant("STEP_TAP_CON") == Int(stepTapCon)
               && constant("STEP_TEXT") == Int(stepText)
               && constant("STEP_WAIT") == Int(stepWait))
    }

    // The firmware that ships alongside must actually carry the marker.
    if let onDisk = try? Data(contentsOf: firmwareImage) {
        assert((try? patchedFirmware([UInt8](onDisk), with: blob)) != nil,
               "firmware/keypad.bin has no keymap marker - rebuild it")
    }

    let roundTrip = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("bbn-check.json")
    try saveSpecs([mac, lit], to: roundTrip)
    let back = loadSpecs(from: roundTrip)
    assert(back?[0].steps.count == 4)
    assert(back?[1].led.mode == .breathe && back?[1].led.periodMs == 1500)
    assert(try! keymapBlob(back![0], back![1]) == (try! keymapBlob(mac, lit)))
    // A keymap.json written before macros existed still loads.
    try Data("""
    [{"keyLabel":"a","mode":"key","mods":[false,false,false,false],"text":"",
      "led":{"blue":1,"green":0,"lightWhilePressed":true,"mode":"off","periodMs":2000,
             "pressBlue":1,"pressGreen":1}},
     {"keyLabel":"b","mode":"key","mods":[false,false,false,false],"text":"",
      "led":{"blue":1,"green":0,"lightWhilePressed":true,"mode":"off","periodMs":2000,
             "pressBlue":1,"pressGreen":1}}]
    """.utf8).write(to: roundTrip)
    assert(loadSpecs(from: roundTrip)?[1].keyLabel == "b")
    try? FileManager.default.removeItem(at: roundTrip)
    assert(loadSpecs(from: URL(fileURLWithPath: "/nonexistent/x.json")) == nil)

    print("check OK: keymap blob and firmware patching verified")
}
