import SwiftUI

/// Custom toggle style that shows accent color when on
struct AccentToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label

            RoundedRectangle(cornerRadius: 8)
                .fill(configuration.isOn ? Color.accentColor : Color(nsColor: .separatorColor))
                .frame(width: 32, height: 18)
                .overlay(
                    Circle()
                        .fill(.white)
                        .shadow(radius: 1)
                        .padding(2)
                        .offset(x: configuration.isOn ? 7 : -7)
                )
                .animation(.easeInOut(duration: 0.15), value: configuration.isOn)
                .onTapGesture {
                    configuration.isOn.toggle()
                }
        }
    }
}

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
                    Text(environment.interfaceIPs.joined(separator: ", "))
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
            .toggleStyle(AccentToggleStyle())
            .labelsHidden()
            .disabled(isToggleDisabled || environment.isTransitioning)
            .opacity(isToggleDisabled || environment.isTransitioning ? 0.5 : 1.0)
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
                    interfaces: [Interface(ip: "127.0.0.2"), Interface(ip: "127.0.0.3")]
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
