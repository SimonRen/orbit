import SwiftUI

/// A card displaying service information and controls
struct ServiceCardView: View {
    let service: Service
    let isEnvironmentActive: Bool
    let isEnvironmentTransitioning: Bool
    let isToggleDisabled: Bool
    let onToggle: (Bool) -> Void
    let onViewLogs: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            StatusDotView(status: service.status)

            // Service info
            VStack(alignment: .leading, spacing: 4) {
                Text(service.name)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Image(systemName: "link")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Port: \(service.portsDisplay)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Error indicator
            if service.status == .failed, let error = service.lastError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .help(error)
            }

            // View logs button
            Button(action: onViewLogs) {
                Image(systemName: "terminal")
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .help("View Logs")

            // Enable/disable toggle
            // Allow toggling ON if service is stopped/failed, even if other checks fail
            let canToggleOn = !service.isEnabled && (service.status == .stopped || service.status == .failed)
            Toggle("", isOn: Binding(
                get: { service.isEnabled },
                set: { onToggle($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
            .disabled(!canToggleOn && (isToggleDisabled || isEnvironmentTransitioning || service.status.isTransitioning))

            // Context menu button
            Menu {
                Button(action: onViewLogs) {
                    Label("View Logs", systemImage: "doc.text")
                }

                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil")
                }
                .disabled(isEnvironmentTransitioning || service.status == .running || service.status.isTransitioning)

                Divider()

                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 24)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isHovered ? Color.accentColor.opacity(0.5) : Color(nsColor: .separatorColor),
                    lineWidth: 1
                )
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        ServiceCardView(
            service: Service(
                name: "auth-service-v2",
                ports: "8080",
                command: "kubectl port-forward svc/auth $IP:8080:8080"
            ),
            isEnvironmentActive: false,
            isEnvironmentTransitioning: false,
            isToggleDisabled: false,
            onToggle: { _ in },
            onViewLogs: {},
            onEdit: {},
            onDelete: {}
        )

        ServiceCardView(
            service: {
                var s = Service(
                    name: "payment-gateway",
                    ports: "3000,3001",
                    command: "ssh -L $IP:3000:localhost:3000"
                )
                s.status = .running
                return s
            }(),
            isEnvironmentActive: true,
            isEnvironmentTransitioning: false,
            isToggleDisabled: false,
            onToggle: { _ in },
            onViewLogs: {},
            onEdit: {},
            onDelete: {}
        )

        ServiceCardView(
            service: {
                var s = Service(
                    name: "frontend-assets",
                    ports: "4200",
                    command: "npm run start"
                )
                s.status = .failed
                s.lastError = "Process exited with code 1"
                return s
            }(),
            isEnvironmentActive: true,
            isEnvironmentTransitioning: false,
            isToggleDisabled: false,
            onToggle: { _ in },
            onViewLogs: {},
            onEdit: {},
            onDelete: {}
        )
    }
    .padding()
    .frame(width: 500)
}
