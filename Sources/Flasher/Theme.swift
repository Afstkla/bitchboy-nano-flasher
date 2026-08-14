import SwiftUI

struct Theme {
    let name: String
    let win95: Bool
    let bg: Color
    let surface: Color
    let surfaceBorder: Color
    let capTop: Color
    let capBottom: Color
    let capText: Color
    let accent: Color
    let text: Color
    let dim: Color
    let consoleBg: Color
    let consoleText: Color
    let fieldBg: Color
    let fieldText: Color
    let buttonText: Color
    let radius: CGFloat
    let dark: Bool

    // bitchboynano.afstkla.nl - paper, ink, signal orange, the pad itself in black
    static let nano = Theme(
        name: "NANO", win95: false,
        bg: Color(hex: 0xE8E8E3), surface: Color(hex: 0xF2F2EE),
        surfaceBorder: Color(hex: 0xC6C6BE),
        capTop: Color(hex: 0x2C2C27), capBottom: Color(hex: 0x1A1A17),
        capText: Color(hex: 0xE8E8E3),
        accent: Color(hex: 0xFF4A00),
        text: Color(hex: 0x101010), dim: Color(hex: 0x5B5B54),
        consoleBg: Color(hex: 0x1A1A17), consoleText: Color(hex: 0xE8E8E3),
        fieldBg: .white, fieldText: Color(hex: 0x101010),
        buttonText: Color(hex: 0xF2F2EE),
        radius: 10, dark: false)

    // bitchboy.lol - Windows 95: silver bevels, navy title bar, pink + neon green
    static let win95 = Theme(
        name: "95", win95: true,
        bg: Color(hex: 0xDFDFDF), surface: Color(hex: 0xDFDFDF),
        surfaceBorder: Color(hex: 0x808080),
        capTop: Color(hex: 0xEFEFEF), capBottom: Color(hex: 0xDFDFDF),
        capText: .black,
        accent: Color(hex: 0xFF0080),
        text: .black, dim: Color(hex: 0x666666),
        consoleBg: .black, consoleText: Color(hex: 0x00FF80),
        fieldBg: .white, fieldText: .black,
        buttonText: .black,
        radius: 0, dark: false)

    static let all: [Theme] = [.nano, .win95]
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

let win95TitleBar = LinearGradient(
    colors: [Color(hex: 0x000080), Color(hex: 0x1084D0)],
    startPoint: .leading, endPoint: .trailing)

struct Bevel: ViewModifier {
    let raised: Bool
    var width: CGFloat = 2

    func body(content: Content) -> some View {
        let light = Color.white
        let dark = Color(hex: 0x808080)
        let darker = Color(hex: 0x404040)
        content
            .overlay(alignment: .top) { (raised ? light : darker).frame(height: width) }
            .overlay(alignment: .leading) { (raised ? light : darker).frame(width: width) }
            .overlay(alignment: .bottom) { (raised ? darker : light).frame(height: width) }
            .overlay(alignment: .trailing) { (raised ? darker : light).frame(width: width) }
            .overlay(alignment: .bottom) { (raised ? dark : light).frame(height: width / 2) }
            .overlay(alignment: .trailing) { (raised ? dark : light).frame(width: width / 2) }
    }
}

extension View {
    @ViewBuilder
    func panelStyle(_ theme: Theme, raised: Bool = true) -> some View {
        if theme.win95 {
            self.background(theme.surface).modifier(Bevel(raised: raised))
        } else {
            self.background(
                RoundedRectangle(cornerRadius: theme.radius)
                    .fill(theme.surface)
                    .overlay(RoundedRectangle(cornerRadius: theme.radius)
                        .strokeBorder(theme.surfaceBorder, lineWidth: 1)))
        }
    }
}
