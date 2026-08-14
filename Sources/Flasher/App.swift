import SwiftUI

@main
enum Main {
    static func main() throws {
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
    @State private var specs = [KeySpec(), KeySpec(keyLabel: "b")]
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
            flashButton
            console
        }
        .padding(theme.win95 ? 12 : 22)
        .frame(width: 480)
        .background(theme.bg)
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
                Button(t.name) { themeName = t.name }
                    .buttonStyle(.plain)
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
            }
        }
        .padding(.trailing, 8)
    }

    private var pad: some View {
        HStack(spacing: 16) {
            ForEach(0..<2) { i in
                Keycap(legend: specs[i].legend, index: i,
                       isSelected: selected == i, theme: theme)
                    .onTapGesture { selected = i }
            }
        }
    }

    private var flashButton: some View {
        Button {
            runner.running ? runner.cancel() : runner.flash(specs[0], specs[1])
        } label: {
            HStack(spacing: 8) {
                Image(systemName: runner.running ? "xmark" : "bolt.fill")
                Text(runner.running ? "Cancel" : "Build & Flash")
            }
            .font(.system(size: 14, weight: .bold,
                          design: theme.win95 ? .monospaced : .default))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .foregroundStyle(runner.running ? theme.dim : theme.buttonText)
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
            capBody
                .frame(width: 150, height: 110)
                .shadow(color: !theme.win95 && isSelected
                        ? theme.accent.opacity(0.35) : .clear, radius: 14)
                .animation(.easeOut(duration: 0.15), value: isSelected)

            Text("KEY \(index + 1)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(2)
                .foregroundStyle(isSelected ? theme.accent : theme.dim)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder private var capBody: some View {
        let label = Text(legend)
            .font(.system(size: legend.count > 5 ? 15 : 24,
                          weight: .bold, design: .monospaced))
            .foregroundStyle(isSelected ? theme.accent : theme.capText)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(.horizontal, 10)

        if theme.win95 {
            ZStack {
                theme.capTop
                label
            }
            .modifier(Bevel(raised: !isSelected, width: 3))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(LinearGradient(colors: [theme.capTop, theme.capBottom],
                                         startPoint: .top, endPoint: .bottom))
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(isSelected ? theme.accent : theme.surfaceBorder,
                                  lineWidth: isSelected ? 2 : 1)
                label
            }
        }
    }
}

struct ConfigPanel: View {
    @Binding var spec: KeySpec
    let theme: Theme
    @StateObject private var recorder = ComboRecorder()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Segment(options: ["Key combo", "Type text"],
                    index: Binding(
                        get: { spec.mode == .key ? 0 : 1 },
                        set: { spec.mode = $0 == 0 ? .key : .text }),
                    theme: theme)

            if spec.mode == .key {
                HStack(spacing: 8) {
                    ForEach(modifiers.indices, id: \.self) { i in
                        ModifierToggle(symbol: modifiers[i].symbol,
                                       isOn: $spec.mods[i],
                                       disabled: keyOption(spec.keyLabel).kind == .con,
                                       theme: theme)
                    }
                    recordButton
                    Spacer()
                    KeyDropdown(selection: $spec.keyLabel, theme: theme)
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
                    .background(theme.win95
                                ? AnyView(theme.fieldBg.modifier(Bevel(raised: false)))
                                : AnyView(RoundedRectangle(cornerRadius: theme.radius - 2)
                                    .fill(theme.fieldBg)
                                    .overlay(RoundedRectangle(cornerRadius: theme.radius - 2)
                                        .strokeBorder(theme.surfaceBorder))))
                Text("Typed once per press · newline is sent as Enter · ASCII only")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.dim)
            }
        }
        .padding(14)
        .panelStyle(theme)
        .onDisappear { recorder.stop() }
    }

    private var hint: String {
        if recorder.recording { return "Recording — press a key combo on your keyboard …" }
        return keyOption(spec.keyLabel).kind == .con
            ? "Media key — modifiers don't apply"
            : "Held down for as long as the button is held"
    }

    private var recordButton: some View {
        Button {
            recorder.recording ? recorder.stop() : recorder.start { mods, label in
                spec.mods = mods
                spec.keyLabel = label
            }
        } label: {
            Image(systemName: recorder.recording ? "stop.fill" : "record.circle")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 34, height: 30)
                .background(togglesBackground(active: recorder.recording, theme: theme))
                .foregroundStyle(recorder.recording ? theme.accent : theme.dim)
        }
        .buttonStyle(.plain)
        .help("Record a combo from your keyboard")
    }
}

struct KeyDropdown: View {
    @Binding var selection: String
    let theme: Theme

    var body: some View {
        Menu {
            ForEach(keyOptions, id: \.label) { opt in
                Button(opt.label) { selection = opt.label }
            }
        } label: {
            HStack(spacing: 0) {
                Text(selection)
                    .font(.system(size: 12, design: theme.win95 ? .monospaced : .default))
                    .foregroundStyle(theme.fieldText)
                    .padding(.leading, 8)
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
            .frame(width: 140, height: 26)
            .background(theme.win95
                        ? AnyView(theme.fieldBg.modifier(Bevel(raised: false)))
                        : AnyView(RoundedRectangle(cornerRadius: theme.radius - 2)
                            .fill(theme.fieldBg)
                            .overlay(RoundedRectangle(cornerRadius: theme.radius - 2)
                                .strokeBorder(theme.surfaceBorder))))
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
    }
}

struct Segment: View {
    let options: [String]
    @Binding var index: Int
    let theme: Theme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { i in
                Button(options[i]) { index = i }
                    .buttonStyle(.plain)
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

    var body: some View {
        Button { isOn.toggle() } label: {
            Text(symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 34, height: 30)
                .background(togglesBackground(active: isOn && !disabled, theme: theme))
                .foregroundStyle(isOn && !disabled ? theme.accent : theme.dim)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
    }
}
