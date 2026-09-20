import SwiftUI

struct PortraitAvatar: View {
    let number: Int
    var size: CGFloat = 40

    var body: some View {
        Image("Portrait\(number)")
            .resizable().scaledToFill()
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.16)))
            .accessibilityHidden(true)
    }
}

/// Identifies the selected gateway in the provider switcher.
struct ProviderAvatar: View {
    let provider: Provider
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: provider.symbol)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(provider.tint.gradient, in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.12)))
            .accessibilityHidden(true)
    }
}

struct ChatOptionToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            configuration.label
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .foregroundStyle(configuration.isOn ? Color.blue : Color.secondary)
                .background(configuration.isOn ? Color.blue.opacity(0.1) : Color.primary.opacity(0.04), in: Capsule())
                .overlay(Capsule().strokeBorder(configuration.isOn ? Color.blue.opacity(0.18) : Color.clear))
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

struct TypingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let phase = Int(context.date.timeIntervalSinceReferenceDate * 2) % 3
            HStack(spacing: 5) {
                ForEach(0..<3) { dot in
                    Circle()
                        .fill(.secondary)
                        .frame(width: 7, height: 7)
                        .opacity(reduceMotion || dot == phase ? 0.85 : 0.35)
                        .offset(y: !reduceMotion && dot == phase ? -2 : 0)
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: phase)
        }
        .frame(height: 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Receiving a reply")
    }
}
