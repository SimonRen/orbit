import SwiftUI

/// List of services within an environment
struct ServiceListView: View {
    let services: [Service]
    let isEnvironmentActive: Bool
    let isEnvironmentTransitioning: Bool
    let onToggle: (UUID, Bool) -> Void
    let onViewLogs: (Service) -> Void
    let onEdit: (Service) -> Void
    let onDelete: (Service) -> Void
    let onRestart: (Service) -> Void
    let canToggleService: (UUID) -> Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if services.isEmpty {
                emptyStateView
            } else {
                ForEach(services.sorted { $0.order < $1.order }) { service in
                    ServiceCardView(
                        service: service,
                        isEnvironmentActive: isEnvironmentActive,
                        isEnvironmentTransitioning: isEnvironmentTransitioning,
                        isToggleDisabled: !canToggleService(service.id),
                        onToggle: { enabled in onToggle(service.id, enabled) },
                        onViewLogs: { onViewLogs(service) },
                        onEdit: { onEdit(service) },
                        onDelete: { onDelete(service) },
                        onRestart: { onRestart(service) }
                    )
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "server.rack")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("No Services")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Add a service to get started")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

#Preview {
    VStack(spacing: 24) {
        // Empty state
        ServiceListView(
            services: [],
            isEnvironmentActive: false,
            isEnvironmentTransitioning: false,
            onToggle: { _, _ in },
            onViewLogs: { _ in },
            onEdit: { _ in },
            onDelete: { _ in },
            onRestart: { _ in },
            canToggleService: { _ in true }
        )

        Divider()

        // With services
        ServiceListView(
            services: [
                Service(name: "auth-service", ports: "8080", command: "kubectl port-forward"),
                {
                    var s = Service(name: "payment-gateway", ports: "3000", command: "ssh tunnel")
                    s.status = .running
                    return s
                }()
            ],
            isEnvironmentActive: true,
            isEnvironmentTransitioning: false,
            onToggle: { _, _ in },
            onViewLogs: { _ in },
            onEdit: { _ in },
            onDelete: { _ in },
            onRestart: { _ in },
            canToggleService: { _ in true }
        )
    }
    .padding()
    .frame(width: 500)
}
