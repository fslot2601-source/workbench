import SwiftUI

struct StatusBadge: View {
    let text: String
    let color: Color
    var symbol: String?

    var body: some View {
        HStack(spacing: 5) {
            if let symbol {
                Image(systemName: symbol)
            }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.12), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}
extension SkillEffectiveState {
    var color: Color {
        switch self {
        case .available: .green
        case .disabled: .secondary
        case .missingDependency: .orange
        case .error: .red
        }
    }
}

extension HookRunnableState {
    var color: Color {
        switch self {
        case .ready: .green
        case .disabled: .secondary
        case .needsTrust, .changedSinceTrust: .orange
        case .unsupportedHandler: .red
        }
    }
}
