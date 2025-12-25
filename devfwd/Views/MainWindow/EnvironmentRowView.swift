import SwiftUI

/// A single row in the environments sidebar
struct EnvironmentRowView: View {
    let environment: DevEnvironment
    let isSelected: Bool
    let isToggleDisabled: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 8) {
            // Environment icon (animate when transitioning)
            if environment.isTransitioning {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 20, height: 16)
            } else {
                Image(systemName: environment.isEnabled ? "cube.fill" : "cube")
                    .foregroundColor(environment.isEnabled ? .accentColor : .secondary)
                    .frame(width: 20)
            }

            // Environment name and interfaces
            VStack(alignment: .leading, spacing: 2) {
                Text(environment.name)
                    .lineLimit(1)
                    .truncationMode(.tail)

                // Interface IPs
                if !environment.interfaces.isEmpty {
                    Text(environment.interfaces.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer()

            // Enable toggle
            Toggle("", isOn: Binding(
                get: { environment.isEnabled },
                set: { onToggle($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
            .disabled(isToggleDisabled || environment.isTransitioning)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        )
        .contentShape(Rectangle())
    }
}

#Preview {
    VStack(spacing: 8) {
        EnvironmentRowView(
            environment: DevEnvironment(name: "Local Dev"),
            isSelected: true,
            isToggleDisabled: false,
            onToggle: { _ in }
        )

        EnvironmentRowView(
            environment: {
                var env = DevEnvironment(
                    name: "Staging-2",
                    interfaces: ["127.0.0.2", "127.0.0.3"]
                )
                env.isEnabled = true
                return env
            }(),
            isSelected: false,
            isToggleDisabled: false,
            onToggle: { _ in }
        )

        EnvironmentRowView(
            environment: {
                var env = DevEnvironment(name: "Transitioning")
                env.isTransitioning = true
                return env
            }(),
            isSelected: false,
            isToggleDisabled: false,
            onToggle: { _ in }
        )

        EnvironmentRowView(
            environment: DevEnvironment(name: "Very Long Environment Name That Should Truncate"),
            isSelected: false,
            isToggleDisabled: false,
            onToggle: { _ in }
        )
    }
    .padding()
    .frame(width: 220)
}
