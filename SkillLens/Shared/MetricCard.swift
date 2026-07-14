import AppKit
import SwiftUI

enum WorkbenchTheme {
    static let accent = Color(red: 0.16, green: 0.43, blue: 0.67)
    static let canvas = adaptive(
        light: NSColor(srgbRed: 0.935, green: 0.944, blue: 0.949, alpha: 1),
        dark: NSColor(srgbRed: 0.105, green: 0.112, blue: 0.118, alpha: 1)
    )
    static let sidebar = adaptive(
        light: NSColor(srgbRed: 0.902, green: 0.916, blue: 0.924, alpha: 1),
        dark: NSColor(srgbRed: 0.125, green: 0.132, blue: 0.139, alpha: 1)
    )
    static let panel = adaptive(
        light: NSColor(srgbRed: 0.958, green: 0.964, blue: 0.968, alpha: 1),
        dark: NSColor(srgbRed: 0.135, green: 0.142, blue: 0.149, alpha: 1)
    )
    static let card = adaptive(
        light: NSColor(srgbRed: 0.977, green: 0.980, blue: 0.982, alpha: 1),
        dark: NSColor(srgbRed: 0.155, green: 0.162, blue: 0.170, alpha: 1)
    )
    static let subtleFill = adaptive(
        light: NSColor(srgbRed: 0.885, green: 0.900, blue: 0.910, alpha: 1),
        dark: NSColor(srgbRed: 0.205, green: 0.215, blue: 0.225, alpha: 1)
    )
    static let separator = adaptive(
        light: NSColor(srgbRed: 0.72, green: 0.75, blue: 0.77, alpha: 0.55),
        dark: NSColor(srgbRed: 0.45, green: 0.47, blue: 0.49, alpha: 0.42)
    )

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(tint)
                Spacer()
                Text(value)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
            }
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 145, alignment: .topLeading)
        .background(WorkbenchTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(WorkbenchTheme.separator, lineWidth: 0.7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(value)，\(subtitle)")
    }
}
