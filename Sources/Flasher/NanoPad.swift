import SwiftUI

struct GraphGrid: View {
    let line: Color
    var cell: CGFloat = 26

    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x: CGFloat = 0
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += cell
            }
            var y: CGFloat = 0
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += cell
            }
            context.stroke(path, with: .color(line), lineWidth: 1)
        }
    }
}

// The pad drawn as on bitchboynano.afstkla.nl: dark enclosure, light keycaps,
// USB notch, and technical-drawing dimension lines with the real size in mm.
struct NanoPad: View {
    let specs: [KeySpec]
    @Binding var selected: Int
    let theme: Theme

    private let bodyHeight: CGFloat = 190

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 8) {
                enclosure
                DimensionLine(label: "58.0", vertical: false, theme: theme)
                    .frame(height: 14)
            }
            DimensionLine(label: "34.0", vertical: true, theme: theme)
                .frame(width: 14, height: bodyHeight)
        }
    }

    private var enclosure: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(LinearGradient(colors: [Color(hex: 0x24241F), Color(hex: 0x161613)],
                                     startPoint: .top, endPoint: .bottom))
            VStack(spacing: 12) {
                HStack(spacing: 18) {
                    ForEach(0..<2) { i in
                        NanoKeycap(legend: specs[i].legend, number: i + 1,
                                   isSelected: selected == i, theme: theme)
                            .onTapGesture { selected = i }
                    }
                }
                Text("BITCHBOY NANO · 1209:0001")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(Color(hex: 0x8B8B80))
            }
            .padding(.top, 6)
        }
        .frame(height: bodyHeight)
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 2)
                .fill(.black)
                .frame(width: 54, height: 5)
                .offset(y: -2)
        }
    }
}

struct NanoKeycap: View {
    let legend: String
    let number: Int
    let isSelected: Bool
    let theme: Theme

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(hex: 0x0D0D0B))
                .offset(y: 4)
            RoundedRectangle(cornerRadius: 7)
                .fill(LinearGradient(colors: [Color(hex: 0xFDFDFB), Color(hex: 0xC9C9C0)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(isSelected ? theme.accent : .black.opacity(0.25),
                                  lineWidth: isSelected ? 2 : 1))
            Text(legend)
                .font(.system(size: legend.count > 5 ? 14 : 22,
                              weight: .bold, design: .monospaced))
                .foregroundStyle(isSelected ? theme.accent : theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(String(format: "%02d", number))
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(isSelected ? theme.accent : theme.dim)
                .padding(6)
        }
        .frame(width: 140, height: 118)
        .animation(.easeOut(duration: 0.15), value: isSelected)
        .contentShape(Rectangle())
    }
}

struct DimensionLine: View {
    let label: String
    let vertical: Bool
    let theme: Theme

    var body: some View {
        ZStack {
            tick.frame(maxWidth: vertical ? nil : .infinity,
                       maxHeight: vertical ? .infinity : nil,
                       alignment: vertical ? .top : .leading)
            line
            tick.frame(maxWidth: vertical ? nil : .infinity,
                       maxHeight: vertical ? .infinity : nil,
                       alignment: vertical ? .bottom : .trailing)
            Text(label)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(theme.dim)
                .rotationEffect(vertical ? .degrees(90) : .zero)
                .fixedSize()
                .padding(vertical ? .vertical : .horizontal, 3)
                .background(theme.bg)
        }
    }

    private var line: some View {
        Rectangle().fill(theme.surfaceBorder)
            .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
    }

    private var tick: some View {
        Rectangle().fill(theme.surfaceBorder)
            .frame(width: vertical ? 9 : 1, height: vertical ? 1 : 9)
    }
}
