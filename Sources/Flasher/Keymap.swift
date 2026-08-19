import Foundation

enum KeyKind { case kbd, con }

struct KeyOption: Hashable {
    let label: String
    let kind: KeyKind
    let expr: String
    let legend: String
}

struct Modifier {
    let symbol: String
    let name: String
    let expr: String
}

let modifiers: [Modifier] = [
    Modifier(symbol: "⌃", name: "control", expr: "KBD_KEY_LEFT_CTRL"),
    Modifier(symbol: "⌥", name: "option", expr: "KBD_KEY_LEFT_ALT"),
    Modifier(symbol: "⇧", name: "shift", expr: "KBD_KEY_LEFT_SHIFT"),
    Modifier(symbol: "⌘", name: "command", expr: "KBD_KEY_LEFT_GUI"),
]

let keyOptions: [KeyOption] = {
    var opts: [KeyOption] = []
    for ch in "abcdefghijklmnopqrstuvwxyz0123456789" {
        opts.append(KeyOption(label: String(ch), kind: .kbd, expr: "'\(ch)'",
                              legend: String(ch).uppercased()))
    }
    let specials: [(String, String, String)] = [
        ("Space", "' '", "␣"), ("Enter", "KBD_KEY_RETURN", "⏎"),
        ("Escape", "KBD_KEY_ESC", "⎋"), ("Tab", "KBD_KEY_TAB", "⇥"),
        ("Backspace", "KBD_KEY_BACKSPACE", "⌫"), ("Delete", "KBD_KEY_DELETE", "⌦"),
        ("Up", "KBD_KEY_UP_ARROW", "↑"), ("Down", "KBD_KEY_DOWN_ARROW", "↓"),
        ("Left", "KBD_KEY_LEFT_ARROW", "←"), ("Right", "KBD_KEY_RIGHT_ARROW", "→"),
        ("Home", "KBD_KEY_HOME", "↖"), ("End", "KBD_KEY_END", "↘"),
        ("Page Up", "KBD_KEY_PAGE_UP", "⇞"), ("Page Down", "KBD_KEY_PAGE_DOWN", "⇟"),
    ]
    for (label, expr, legend) in specials {
        opts.append(KeyOption(label: label, kind: .kbd, expr: expr, legend: legend))
    }
    for n in 1...24 {
        opts.append(KeyOption(label: "F\(n)", kind: .kbd, expr: "KBD_KEY_F\(n)", legend: "F\(n)"))
    }
    let media: [(String, String, String)] = [
        ("Play/Pause", "0xCD", "⏯"), ("Next Track", "CON_MEDIA_NEXT", "⏭"),
        ("Previous Track", "CON_MEDIA_PREV", "⏮"), ("Volume Up", "CON_VOL_UP", "VOL+"),
        ("Volume Down", "CON_VOL_DOWN", "VOL−"), ("Mute", "CON_VOL_MUTE", "MUTE"),
    ]
    for (label, expr, legend) in media {
        opts.append(KeyOption(label: label, kind: .con, expr: expr, legend: legend))
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

    var expr: String { "LED_MODE_" + rawValue.uppercased() }

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

func cString(_ text: String) throws -> String {
    let folded = text.map { asciiFolds[$0] ?? String($0) }.joined()
    var out = "\""
    for ch in folded.unicodeScalars {
        switch ch {
        case "\\": out += "\\\\"
        case "\"": out += "\\\""
        case "\n": out += "\\n"
        case "\t": out += "\\t"
        case let c where c.value >= 32 && c.value < 127: out.unicodeScalars.append(c)
        default: throw KeymapError(message: "only plain ASCII can be typed, not '\(ch)'")
        }
    }
    return out + "\""
}

func stepCode(_ step: MacroStep) throws -> String {
    switch step.kind {
    case .wait:
        return "DLY_ms(\(Int(step.waitMs)));"
    case .text:
        return "KBD_print(\(try cString(step.text)));"
    case .tap:
        let opt = keyOption(step.keyLabel)
        if opt.kind == .con { return "CON_type(\(opt.expr));" }
        let mods = zip(modifiers, step.mods).filter { $0.1 }.map { $0.0.expr }
        return mods.map { "KBD_press(\($0)); " }.joined()
            + "KBD_type(\(opt.expr));"
            + mods.reversed().map { " KBD_release(\($0));" }.joined()
    }
}

func macros(_ n: Int, _ spec: KeySpec) throws -> String {
    if spec.mode == .macro {
        let body = try spec.steps.map { "  " + (try stepCode($0)) + " \\\n" }.joined()
        return """
        #define KEY\(n)_PRESSED()  { \\
        \(body)}
        #define KEY\(n)_RELEASED() { }

        """
    }
    if spec.mode == .text {
        let literal = try cString(spec.text)
        return """
        #define KEY\(n)_PRESSED()  { KBD_print(\(literal)); }
        #define KEY\(n)_RELEASED() { }

        """
    }
    let opt = keyOption(spec.keyLabel)
    if opt.kind == .con {
        return """
        #define KEY\(n)_PRESSED()  { CON_press(\(opt.expr)); }
        #define KEY\(n)_RELEASED() { CON_release(\(opt.expr)); }

        """
    }
    let mods = zip(modifiers, spec.mods).filter { $0.1 }.map { $0.0.expr }
    let press = mods.map { "KBD_press(\($0)); " }.joined() + "KBD_press(\(opt.expr));"
    let release = "KBD_release(\(opt.expr));"
        + mods.reversed().map { " KBD_release(\($0));" }.joined()
    return """
    #define KEY\(n)_PRESSED()  { \(press) }
    #define KEY\(n)_RELEASED() { \(release) }

    """
}

func ledMacros(_ n: Int, _ led: LedSpec) -> String {
    """
    #define KEY\(n)_LED_MODE      \(led.mode.expr)
    #define KEY\(n)_LED_G         \(level(led.green))
    #define KEY\(n)_LED_B         \(level(led.blue))
    #define KEY\(n)_LED_PERIOD_MS \(Int(led.periodMs))
    #define KEY\(n)_LED_PRESS     \(led.lightWhilePressed ? 1 : 0)
    #define KEY\(n)_LED_PRESS_G   \(level(led.pressGreen))
    #define KEY\(n)_LED_PRESS_B   \(level(led.pressBlue))

    """
}

// The WCH bootloader cannot read flash back, so what is on the pad can never be
// queried - this sidecar next to keymap.h is the closest thing to remembering it.
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

func keymapFile(_ spec1: KeySpec, _ spec2: KeySpec) throws -> String {
    try "// Generated by the BitchBoy Nano flasher - do not edit by hand.\n\n#pragma once\n\n"
        + macros(1, spec1) + "\n" + macros(2, spec2) + "\n"
        + ledMacros(1, spec1.led) + "\n" + ledMacros(2, spec2.led)
}

func runCheck() throws {
    var s1 = KeySpec()
    s1.mods = [true, false, false, true]
    s1.keyLabel = "F13"
    var s2 = KeySpec(mode: .text)
    s2.text = "echo \"hi \\ there\"\nsecond line"

    let keymap = try keymapFile(s1, s2)
    assert(keymap.contains("KBD_press(KBD_KEY_LEFT_CTRL); KBD_press(KBD_KEY_LEFT_GUI); KBD_press(KBD_KEY_F13);"))
    assert(keymap.contains("KBD_release(KBD_KEY_F13); KBD_release(KBD_KEY_LEFT_GUI); KBD_release(KBD_KEY_LEFT_CTRL);"))
    assert(keymap.contains("KBD_print(\"echo \\\"hi \\\\ there\\\"\\nsecond line\");"))
    assert(s1.legend == "⌃⌘F13")
    assert((try? cString("héllo")) == nil, "non-ASCII should be rejected")
    assert(try! cString("Hi, I\u{2019}m \u{201C}Nano\u{201D} \u{2014} ok\u{2026}")
        == "\"Hi, I'm \\\"Nano\\\" - ok...\"")

    var mac = KeySpec(mode: .macro)
    mac.steps = [
        MacroStep(kind: .tap, mods: [false, false, false, true], keyLabel: "Space"),
        MacroStep(kind: .wait, waitMs: 100),
        MacroStep(kind: .text, text: "terminal\n"),
        MacroStep(kind: .wait, waitMs: 250),
        MacroStep(kind: .tap, keyLabel: "Volume Up"),
    ]
    let macro = try macros(1, mac)
    assert(macro.contains("KBD_press(KBD_KEY_LEFT_GUI); KBD_type(' '); KBD_release(KBD_KEY_LEFT_GUI); \\\n"))
    assert(macro.contains("  DLY_ms(100); \\\n"))
    assert(macro.contains("  KBD_print(\"terminal\\n\"); \\\n"))
    assert(macro.contains("  CON_type(CON_VOL_UP); \\\n"))
    assert(macro.contains("#define KEY1_RELEASED() { }"))
    assert(mac.legend == "▶5")
    assert(try! macros(2, KeySpec(mode: .macro)).contains("#define KEY2_PRESSED()  { \\\n}"))

    var media = KeySpec()
    media.keyLabel = "Volume Up"
    assert(try! macros(1, media).contains("CON_press(CON_VOL_UP)"))

    var lit = KeySpec()
    lit.led = LedSpec(mode: .breathe, green: 1, blue: 0, periodMs: 1500,
                      lightWhilePressed: true, pressGreen: 0, pressBlue: 1)
    let leds = ledMacros(2, lit.led)
    assert(leds.contains("#define KEY2_LED_MODE      LED_MODE_BREATHE"))
    assert(leds.contains("#define KEY2_LED_G         255"))
    assert(leds.contains("#define KEY2_LED_B         0"))
    assert(leds.contains("#define KEY2_LED_PERIOD_MS 1500"))
    assert(leds.contains("#define KEY2_LED_PRESS     1"))
    assert(leds.contains("#define KEY2_LED_PRESS_B   255"))
    assert(level(0.5) == 128 && level(-1) == 0 && level(2) == 255)
    assert(ledMacros(1, LedSpec()).contains("#define KEY1_LED_MODE      LED_MODE_OFF"))

    let roundTrip = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("bbn-check.json")
    try saveSpecs([s1, lit], to: roundTrip)
    let back = loadSpecs(from: roundTrip)
    assert(back?[0].keyLabel == "F13" && back?[0].mods == [true, false, false, true])
    assert(back?[1].led.mode == .breathe && back?[1].led.periodMs == 1500)
    try saveSpecs([mac, s2], to: roundTrip)
    assert(loadSpecs(from: roundTrip)?[0].steps.count == 5)
    assert(try! keymapFile(loadSpecs(from: roundTrip)![0], s2) == (try! keymapFile(mac, s2)))
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
    assert(try! keymapFile(back![0], back![1]) == (try! keymapFile(s1, lit)))
    try? FileManager.default.removeItem(at: roundTrip)
    assert(loadSpecs(from: URL(fileURLWithPath: "/nonexistent/x.json")) == nil)

    print("check OK: keymap generation verified")
}
