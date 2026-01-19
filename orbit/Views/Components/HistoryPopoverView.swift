import SwiftUI

/// Popover view for browsing and restoring environment history snapshots
struct HistoryPopoverView: View {
    let environment: DevEnvironment
    let onRestore: (Int) -> Void  // snapshot index
    @State private var confirmRestoreIndex: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Text("History")
                .font(.headline)
                .padding()

            Divider()

            if environment.history.isEmpty {
                // Empty state
                VStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No history yet")
                        .foregroundColor(.secondary)
                    Text("Changes will appear here")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
            } else {
                // History list
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(environment.history.enumerated()), id: \.offset) { index, snapshot in
                            HistoryRowView(
                                snapshot: snapshot,
                                onRestore: { confirmRestoreIndex = index }
                            )
                            if index < environment.history.count - 1 {
                                Divider().padding(.leading, 12)
                            }
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
        }
        .frame(width: 280)
        .alert("Restore Environment?", isPresented: .init(
            get: { confirmRestoreIndex != nil },
            set: { if !$0 { confirmRestoreIndex = nil } }
        )) {
            Button("Cancel", role: .cancel) { }
            Button("Restore", role: .destructive) {
                if let index = confirmRestoreIndex {
                    onRestore(index)
                }
            }
        } message: {
            Text("This will revert the environment to this snapshot. Your current state will be saved to history.")
        }
    }
}

/// Row view for a single history snapshot
struct HistoryRowView: View {
    let snapshot: HistorySnapshot
    let onRestore: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.timestamp.relativeFormatted())
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("\"\(snapshot.data.name)\", \(snapshot.data.services.count) services")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Restore") {
                onRestore()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Date Extension for Relative Formatting

extension Date {
    /// Format date as relative string (e.g., "5 min ago", "Yesterday")
    func relativeFormatted() -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}

#Preview("With History") {
    HistoryPopoverView(
        environment: DevEnvironment(
            name: "DEV",
            interfaces: [Interface(ip: "127.0.0.2")],
            services: [
                Service(name: "API", ports: "8080", command: "echo test", order: 0)
            ],
            history: [
                HistorySnapshot(from: DevEnvironment(name: "DEV", services: [
                    Service(name: "API", ports: "8080", command: "echo test", order: 0),
                    Service(name: "Web", ports: "3000", command: "echo web", order: 1),
                    Service(name: "Worker", ports: "9000", command: "echo worker", order: 2)
                ])),
                HistorySnapshot(from: DevEnvironment(name: "Development", services: [
                    Service(name: "API", ports: "8080", command: "echo test", order: 0),
                    Service(name: "Web", ports: "3000", command: "echo web", order: 1)
                ])),
                HistorySnapshot(from: DevEnvironment(name: "Development", services: [
                    Service(name: "API", ports: "8080", command: "echo test", order: 0)
                ]))
            ]
        ),
        onRestore: { _ in }
    )
    .padding()
}

#Preview("Empty") {
    HistoryPopoverView(
        environment: DevEnvironment(name: "DEV", history: []),
        onRestore: { _ in }
    )
    .padding()
}
