import SwiftUI

@main
enum Main {
    static func main() throws {
        setvbuf(stdout, nil, _IONBF, 0)     // unbuffered, so a redirected log is live
        if CommandLine.arguments.contains("--check") {
            try runCheck()
        } else {
            FlasherApp.main()
        }
    }
}

struct FlasherApp: App {
    var body: some Scene {
        Window("BitchBoy Nano", id: "main") {
            ContentView()
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .windowResizability(.contentSize)
    }
}

struct ContentView: View {
    @State private var specs = loadSpecs(from: specsFile)
        ?? [KeySpec(), KeySpec(keyLabel: "b")]
    @State private var selected = 0
    @StateObject private var runner = Runner()
    @AppStorage("theme") private var themeName = "NANO"

    private var theme: Theme {
        Theme.all.first { $0.name == themeName } ?? .nano
    }

    var body: some View {
        VStack(spacing: theme.win95 ? 12 : 18) {
            header
            pad
            ConfigPanel(spec: $specs[selected], theme: theme)
            LedPanel(led: $specs[selected].led, theme: theme)
            flashButton
            console
        }
        .padding(theme.win95 ? 12 : 22)
        .frame(width: 480)
        .background {
            theme.bg
            if !theme.win95 { GraphGrid(line: theme.surfaceBorder.opacity(0.45)) }
        }
        .preferredColorScheme(theme.dark ? .dark : .light)
        .tint(theme.accent)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("BITCHBOY NANO")
                .font(.system(size: theme.win95 ? 15 : 19, weight: .heavy,
                              design: .monospaced))
                .tracking(theme.win95 ? 1 : 3)
                .foregroundStyle(theme.win95 ? .white : theme.text)
            Spacer()
            themeSwitch
            HStack(spacing: 5) {
                Circle()
                    .fill(runner.running ? theme.accent : theme.dim.opacity(0.5))
                    .frame(width: 7, height: 7)
                Text(runner.running ? "BUSY" : "IDLE")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.win95 ? .white.opacity(0.85) : theme.dim)
            }
        }
        .padding(.horizontal, theme.win95 ? 8 : 0)
        .padding(.vertical, theme.win95 ? 5 : 0)
        .background { if theme.win95 { win95TitleBar } }
    }

    private var themeSwitch: some View {
        HStack(spacing: 2) {
            ForEach(Theme.all, id: \.name) { t in
                Button { themeName = t.name } label: {
                    Text(t.name)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(themeName == t.name
                                    ? AnyShapeStyle(theme.accent)
                                    : AnyShapeStyle(.clear))
                        .foregroundStyle(themeName == t.name
                                         ? (theme.win95 ? .white : theme.surface)
                                         : (theme.win95 ? .white.opacity(0.7) : theme.dim))
                        .clipShape(RoundedRectangle(cornerRadius: theme.radius / 2))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.trailing, 8)
    }

    @ViewBuilder private var pad: some View {
        if theme.win95 {
            HStack(spacing: 16) {
                ForEach(0..<2) { i in
                    Keycap(legend: specs[i].legend, index: i,
                           isSelected: selected == i, theme: theme)
                        .onTapGesture { selected = i }
                }
            }
        } else {
            NanoPad(specs: specs, selected: $selected, theme: theme)
        }
    }

    private var flashButton: some View {
        Button {
            runner.running ? runner.cancel() : runner.flash(specs[0], specs[1])
        } label: {
            HStack(spacing: 8) {
                Image(systemName: runner.running ? "xmark" : "bolt.fill")
                Text(runner.running ? "Cancel" : "Flash")
            }
            .font(.system(size: 14, weight: .bold,
                          design: theme.win95 ? .monospaced : .default))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .foregroundStyle(runner.running ? theme.dim : theme.buttonText)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(FlashButtonBackground(theme: theme, running: runner.running))
    }

    private var console: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(runner.log.isEmpty ? "> ready" : runner.log)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(runner.log.isEmpty
                                     ? theme.consoleText.opacity(0.5)
                                     : theme.consoleText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(10)
                Color.clear.frame(height: 1).id("bottom")
            }
            .frame(height: 170)
            .background(theme.win95
                        ? AnyView(theme.consoleBg.modifier(Bevel(raised: false)))
                        : AnyView(RoundedRectangle(cornerRadius: theme.radius)
                            .fill(theme.consoleBg)))
            .onChange(of: runner.log) { _ in
                proxy.scrollTo("bottom")
            }
        }
    }
}

struct FlashButtonBackground: ViewModifier {
    let theme: Theme
    let running: Bool

    func body(content: Content) -> some View {
        if theme.win95 {
            content.background(theme.surface).modifier(Bevel(raised: !running))
        } else {
            content.background(
                RoundedRectangle(cornerRadius: theme.radius)
                    .fill(running ? theme.surface : theme.accent))
        }
    }
}

struct Keycap: View {
    let legend: String
    let index: Int
    let isSelected: Bool
    let theme: Theme

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                theme.capTop
                Text(legend)
                    .font(.system(size: legend.count > 5 ? 15 : 24,
                                  weight: .bold, design: .monospaced))
                    .foregroundStyle(isSelected ? theme.accent : theme.capText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 10)
            }
            .modifier(Bevel(raised: !isSelected, width: 3))
            .frame(width: 150, height: 110)

            Text("KEY \(index + 1)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(2)
                .foregroundStyle(isSelected ? theme.accent : theme.dim)
        }
        .contentShape(Rectangle())
    }
}

struct ConfigPanel: View {
    @Binding var spec: KeySpec
    let theme: Theme
    @StateObject private var recorder = ComboRecorder()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Segment(options: KeySpecMode.allCases.map(\.label),
                    index: Binding(
                        get: { KeySpecMode.allCases.firstIndex(of: spec.mode) ?? 0 },
                        set: { spec.mode = KeySpecMode.allCases[$0] }),
                    theme: theme)

            if spec.mode == .macro {
                macroEditor
            } else if spec.mode == .key {
                HStack(spacing: 8) {
                    ForEach(modifiers.indices, id: \.self) { i in
                        ModifierToggle(symbol: modifiers[i].symbol,
                                       isOn: $spec.mods[i],
                                       disabled: keyOption(spec.keyLabel).kind == .con,
                                       theme: theme)
                    }
                    recordButton
                    Spacer()
                    Dropdown(options: keyOptions.map(\.label), selection: $spec.keyLabel, theme: theme)
                }
                Text(hint)
                    .font(.system(size: 10))
                    .foregroundStyle(recorder.recording ? theme.accent : theme.dim)
            } else {
                TextEditor(text: $spec.text)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(theme.fieldText)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(height: 64)
                    .fieldBackground(theme)
                Text("Typed once per press · newline is sent as Enter · ASCII only")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.dim)
            }
        }
        .padding(14)
        .panelStyle(theme)
        .onDisappear { recorder.stop() }
    }

    // ponytail: no scroll view and move-up only - a macro long enough to want either
    // wants a different editor altogether.
    private var macroEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(spec.steps.indices, id: \.self) { i in
                StepRow(step: $spec.steps[i], theme: theme,
                        moveUp: i == 0 ? nil : { spec.steps.swapAt(i, i - 1) },
                        remove: { spec.steps.remove(at: i) })
            }
            HStack(spacing: 6) {
                ForEach(StepKind.allCases, id: \.self) { kind in
                    Button { spec.steps.append(MacroStep(kind: kind)) } label: {
                        Text("+ " + kind.label)
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(togglesBackground(active: false, theme: theme))
                            .foregroundStyle(theme.dim)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                recordButton
            }
            .padding(.top, 2)
            Text(recorder.recording
                 ? "Recording — type the macro here; pauses over 0.4s become Wait steps"
                 : "Runs once per press · the LEDs hold still while it runs")
                .font(.system(size: 10))
                .foregroundStyle(recorder.recording ? theme.accent : theme.dim)
        }
    }

    private var hint: String {
        if recorder.recording { return "Recording — press a key combo on your keyboard …" }
        return keyOption(spec.keyLabel).kind == .con
            ? "Media key — modifiers don't apply"
            : "Held down for as long as the button is held"
    }

    private var recordButton: some View {
        Button {
            if recorder.recording {
                recorder.stop()
            } else if spec.mode == .macro {
                recorder.startMacro { spec.steps.append($0) }
            } else {
                recorder.start { mods, label in
                    spec.mods = mods
                    spec.keyLabel = label
                }
            }
        } label: {
            Image(systemName: recorder.recording ? "stop.fill" : "record.circle")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 34, height: 30)
                .background(togglesBackground(active: recorder.recording, theme: theme))
                .foregroundStyle(recorder.recording ? theme.accent : theme.dim)
        }
        .buttonStyle(.plain)
        .help("Record from your keyboard")
    }
}

struct LedPanel: View {
    @Binding var led: LedSpec
    let theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("LED")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.dim)
                Spacer()
                swatch
            }

            Segment(options: LedMode.allCases.map(\.label),
                    index: Binding(
                        get: { LedMode.allCases.firstIndex(of: led.mode) ?? 0 },
                        set: { led.mode = LedMode.allCases[$0] }),
                    theme: theme)

            if led.mode.usesColour {
                channel("Green", $led.green)
                channel("Blue", $led.blue)
            }

            if led.mode.usesPeriod {
                HStack(spacing: 8) {
                    Text("Speed")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.dim)
                        .frame(width: 42, alignment: .leading)
                    Slider(value: $led.periodMs, in: 200...5000, step: 100)
                    Text("\(Int(led.periodMs)) ms")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(theme.dim)
                        .frame(width: 56, alignment: .trailing)
                }
            }

            Toggle(isOn: $led.lightWhilePressed) {
                Text("Light while pressed")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.fieldText)
            }
            .toggleStyle(.checkbox)

            if led.lightWhilePressed {
                channel("Green", $led.pressGreen)
                channel("Blue", $led.pressBlue)
            }

            Text("These pads wire only green and blue — there is no red channel")
                .font(.system(size: 10))
                .foregroundStyle(theme.dim)
        }
        .padding(14)
        .panelStyle(theme)
    }

    private func channel(_ name: String, _ value: Binding<Double>) -> some View {
        HStack(spacing: 8) {
            Text(name)
                .font(.system(size: 10))
                .foregroundStyle(theme.dim)
                .frame(width: 42, alignment: .leading)
            Slider(value: value, in: 0...1)
            Text("\(Int(value.wrappedValue * 100))%")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(theme.dim)
                .frame(width: 56, alignment: .trailing)
        }
    }

    private var swatch: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color(red: 0, green: led.green, blue: led.blue))
            .frame(width: 34, height: 14)
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(theme.surfaceBorder))
            .opacity(led.mode == .off ? 0.25 : 1)
    }
}

struct Dropdown: View {
    let options: [String]
    @Binding var selection: String
    let theme: Theme
    var width: CGFloat = 140

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { opt in
                Button(opt) { selection = opt }
            }
        } label: {
            HStack(spacing: 0) {
                Text(selection)
                    .font(.system(size: 12, design: theme.win95 ? .monospaced : .default))
                    .foregroundStyle(theme.fieldText)
                    .padding(.leading, 8)
                    .lineLimit(1)
                Spacer()
                if theme.win95 {
                    Text("▼")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 22, height: 22)
                        .background(theme.surface)
                        .modifier(Bevel(raised: true))
                        .padding(2)
                } else {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(theme.dim)
                        .padding(.trailing, 8)
                }
            }
            .frame(width: width, height: 26)
            .fieldBackground(theme)
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
    }
}

struct StepRow: View {
    @Binding var step: MacroStep
    let theme: Theme
    let moveUp: (() -> Void)?
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Dropdown(options: StepKind.allCases.map(\.label),
                     selection: Binding(
                        get: { step.kind.label },
                        set: { label in
                            step.kind = StepKind.allCases.first { $0.label == label } ?? .tap
                        }),
                     theme: theme, width: 78)

            switch step.kind {
            case .tap:
                ForEach(modifiers.indices, id: \.self) { i in
                    ModifierToggle(symbol: modifiers[i].symbol, isOn: $step.mods[i],
                                   disabled: keyOption(step.keyLabel).kind == .con,
                                   theme: theme, size: CGSize(width: 28, height: 26))
                }
                Dropdown(options: keyOptions.map(\.label), selection: $step.keyLabel,
                         theme: theme, width: 112)
            case .text:
                TextEditor(text: $step.text)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(theme.fieldText)
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .frame(height: 40)
                    .fieldBackground(theme)
            case .wait:
                TextField("", value: $step.waitMs, format: .number)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(theme.fieldText)
                    .padding(.horizontal, 6)
                    .frame(width: 64, height: 26)
                    .fieldBackground(theme)
                Text("ms")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.dim)
            }

            Spacer(minLength: 0)
            iconButton("chevron.up", theme: theme, action: moveUp)
            iconButton("xmark", theme: theme, action: remove)
        }
    }
}

func iconButton(_ symbol: String, theme: Theme, action: (() -> Void)?) -> some View {
    Button { action?() } label: {
        Image(systemName: symbol)
            .font(.system(size: 10, weight: .semibold))
            .frame(width: 24, height: 26)
            .background(togglesBackground(active: false, theme: theme))
            .foregroundStyle(theme.dim)
    }
    .buttonStyle(.plain)
    .disabled(action == nil)
    .opacity(action == nil ? 0.3 : 1)
}

struct Segment: View {
    let options: [String]
    @Binding var index: Int
    let theme: Theme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { i in
                Button { index = i } label: {
                    Text(options[i])
                        .font(.system(size: 12, weight: index == i ? .bold : .regular,
                                      design: theme.win95 ? .monospaced : .default))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            index == i
                            ? AnyView(theme.win95
                                      ? AnyView(theme.capTop.modifier(Bevel(raised: false)))
                                      : AnyView(RoundedRectangle(cornerRadius: theme.radius - 2)
                                          .fill(theme.accent)))
                            : AnyView(Color.clear))
                        .foregroundStyle(index == i
                                         ? (theme.win95 ? theme.text : theme.buttonText)
                                         : theme.dim)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }
}

func togglesBackground(active: Bool, theme: Theme) -> some View {
    Group {
        if theme.win95 {
            theme.capTop.modifier(Bevel(raised: !active))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(active ? theme.accent.opacity(0.15) : theme.bg)
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(active ? theme.accent : theme.surfaceBorder))
        }
    }
}

struct ModifierToggle: View {
    let symbol: String
    @Binding var isOn: Bool
    let disabled: Bool
    let theme: Theme
    var size = CGSize(width: 34, height: 30)

    var body: some View {
        Button { isOn.toggle() } label: {
            Text(symbol)
                .font(.system(size: size.height > 28 ? 15 : 13, weight: .semibold))
                .frame(width: size.width, height: size.height)
                .background(togglesBackground(active: isOn && !disabled, theme: theme))
                .foregroundStyle(isOn && !disabled ? theme.accent : theme.dim)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
    }
}

extension View {
    func fieldBackground(_ theme: Theme) -> some View {
        background(theme.win95
                   ? AnyView(theme.fieldBg.modifier(Bevel(raised: false)))
                   : AnyView(RoundedRectangle(cornerRadius: theme.radius - 2)
                       .fill(theme.fieldBg)
                       .overlay(RoundedRectangle(cornerRadius: theme.radius - 2)
                           .strokeBorder(theme.surfaceBorder))))
    }
}
