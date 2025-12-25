import SwiftUI

/// A small colored dot indicating service status
struct StatusDotView: View {
    let status: ServiceStatus

    private var color: Color {
        switch status {
        case .stopped:
            return .gray
        case .starting, .stopping:
            return .yellow
        case .running:
            return .green
        case .failed:
            return .red
        }
    }

    private var shouldPulse: Bool {
        status.isTransitioning
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 10, height: 10)
            .modifier(PulseAnimationModifier(isActive: shouldPulse))
    }
}

/// Applies a pulsing animation when active
struct PulseAnimationModifier: ViewModifier {
    let isActive: Bool
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isActive && isPulsing ? 0.4 : 1.0)
            .animation(
                isActive
                    ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                    : .default,
                value: isPulsing
            )
            .onAppear {
                if isActive {
                    isPulsing = true
                }
            }
            .onChange(of: isActive) { newValue in
                isPulsing = newValue
            }
    }
}

#Preview("All States") {
    HStack(spacing: 20) {
        VStack {
            StatusDotView(status: .stopped)
            Text("Stopped").font(.caption)
        }
        VStack {
            StatusDotView(status: .starting)
            Text("Starting").font(.caption)
        }
        VStack {
            StatusDotView(status: .running)
            Text("Running").font(.caption)
        }
        VStack {
            StatusDotView(status: .failed)
            Text("Failed").font(.caption)
        }
        VStack {
            StatusDotView(status: .stopping)
            Text("Stopping").font(.caption)
        }
    }
    .padding()
}
