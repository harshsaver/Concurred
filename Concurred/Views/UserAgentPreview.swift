import SwiftUI

/// A selection animation, not a live traffic or connectivity indicator.
struct UserAgentPreview: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let preset: UserAgentPreset
    let pulse: Int
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 8) {
            if reduceMotion {
                DeviceSignalScene(device: preset.device, progress: 0)
            } else {
                Color.clear
                    .keyframeAnimator(initialValue: 0.0, trigger: [preset.name, String(pulse), String(appeared)]) { _, progress in
                        DeviceSignalScene(device: preset.device, progress: progress)
                    } keyframes: { _ in
                        MoveKeyframe(0)
                        LinearKeyframe(1, duration: 1.6)
                    }
                    .frame(height: 146)
            }
            Text(preset.name).font(.callout.weight(.semibold))
            Text("User-Agent header only · No device emulation")
                .font(.caption2).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 10).padding(.bottom, 14)
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
        .onAppear { appeared = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("User-Agent preview: \(preset.name). Changes the request header only.")
    }
}

struct DeviceSignalScene: View {
    let device: UserAgentPreset.Device
    let progress: Double

    private var tint: Color { device == .android ? .green : (device == .terminal ? .orange : .blue) }

    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width * 0.3, y: 91)
            let origin = CGPoint(x: center.x + (device.isPhone ? 22 : 44), y: device.isPhone ? 39 : 57)
            let destination = CGPoint(x: geometry.size.width * 0.83, y: 31)
            let activity = sin(progress * .pi)

            ZStack {
                // The beam visibly originates at the device and widens toward the receiver.
                Path { path in
                    path.move(to: origin)
                    path.addLine(to: CGPoint(x: destination.x - 6, y: destination.y - 12))
                    path.addLine(to: CGPoint(x: destination.x + 8, y: destination.y + 12))
                    path.closeSubpath()
                }
                .fill(LinearGradient(colors: [tint.opacity(0.08 + activity * 0.22), tint.opacity(0.02)],
                                     startPoint: .bottomLeading, endPoint: .topTrailing))

                Path { path in
                    path.move(to: origin)
                    path.addLine(to: destination)
                }
                .stroke(tint.opacity(0.24), style: StrokeStyle(lineWidth: 1.5, dash: [3, 5]))

                ForEach(0..<3) { index in
                    let travel = min(1, max(0, (progress - Double(index) * 0.13) / 0.7))
                    Circle().fill(tint)
                        .frame(width: 5, height: 5)
                        .shadow(color: tint.opacity(0.65), radius: 4)
                        .opacity(sin(travel * .pi))
                        .position(x: origin.x + (destination.x - origin.x) * travel,
                                  y: origin.y + (destination.y - origin.y) * travel)
                }

                Image(systemName: "globe")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(tint)
                    .padding(9)
                    .background(tint.opacity(0.08 + activity * 0.08), in: Circle())
                    .scaleEffect(1 + activity * 0.07)
                    .position(destination)

                DeviceIllustration(device: device)
                    .scaleEffect(1 + activity * 0.025)
                    .position(center)
            }
        }
        .frame(height: 146)
        .accessibilityHidden(true)
    }
}

private struct DeviceIllustration: View {
    let device: UserAgentPreset.Device

    var body: some View {
        ZStack {
            if device.isPhone {
                RoundedRectangle(cornerRadius: 13).fill(Color(white: 0.17))
                    .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(.white.opacity(0.35)))
                    .frame(width: 59, height: 108)
                RoundedRectangle(cornerRadius: 9)
                    .fill((device == .android ? Color.green : Color.blue).opacity(0.2))
                    .frame(width: 49, height: 94)
                Capsule().fill(.black.opacity(0.8)).frame(width: 17, height: 4).offset(y: -43)
                Capsule().fill(.white.opacity(0.65)).frame(width: 18, height: 2).offset(y: 44)
                platformMark
            } else {
                if device == .windows {
                    RoundedRectangle(cornerRadius: 2).fill(Color(white: 0.45))
                        .frame(width: 9, height: 16).offset(y: 36)
                    Capsule().fill(Color(white: 0.6)).frame(width: 44, height: 4).offset(y: 45)
                } else {
                    UnevenRoundedRectangle(bottomLeadingRadius: 5, bottomTrailingRadius: 5)
                        .fill(Color(white: 0.65)).frame(width: 122, height: 7).offset(y: 35)
                }
                RoundedRectangle(cornerRadius: 7).fill(Color(white: 0.16))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.white.opacity(0.35)))
                    .frame(width: 108, height: 70)
                RoundedRectangle(cornerRadius: 3).fill(Color.blue.opacity(0.16))
                    .frame(width: 96, height: 57).offset(y: -1)
                platformMark
            }
        }
        .frame(width: 128, height: 110)
    }

    @ViewBuilder private var platformMark: some View {
        switch device {
        case .mac, .iPhone:
            Image(systemName: "apple.logo").font(.system(size: 27)).foregroundStyle(.white)
        case .windows:
            VStack(spacing: 3) {
                ForEach(0..<2) { _ in
                    HStack(spacing: 3) {
                        ForEach(0..<2) { _ in Rectangle().fill(Color.cyan).frame(width: 13, height: 13) }
                    }
                }
            }
        case .android:
            ZStack {
                Capsule().fill(.green).frame(width: 2, height: 11).rotationEffect(.degrees(-30)).offset(x: -12, y: -12)
                Capsule().fill(.green).frame(width: 2, height: 11).rotationEffect(.degrees(30)).offset(x: 12, y: -12)
                UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18)
                    .fill(.green).frame(width: 36, height: 20)
                HStack(spacing: 12) {
                    Circle().fill(.black).frame(width: 3, height: 3)
                    Circle().fill(.black).frame(width: 3, height: 3)
                }
            }
        case .terminal:
            Text(">_").font(.system(size: 27, weight: .medium, design: .monospaced)).foregroundStyle(.green)
        case .custom:
            Image(systemName: "slider.horizontal.3").font(.system(size: 25)).foregroundStyle(.white)
        }
    }
}
