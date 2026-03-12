import SwiftUI
import AppKit

/// Standalone window view for viewing service logs
struct LogWindowView: View {
    @EnvironmentObject var appState: AppState
    let serviceId: UUID

    @State private var autoScroll = true

    /// Get service using O(1) cache lookup
    private var service: Service? {
        appState.service(for: serviceId)
    }

    /// Logs stored separately for performance (doesn't trigger full environments diff)
    private var logs: [LogEntry] {
        appState.logs(for: serviceId)
    }

    var body: some View {
        Group {
            if let service = service {
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(service.name)
                                .font(.headline)
                            Text("Service Logs")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        // Status indicator
                        HStack(spacing: 6) {
                            StatusDotView(status: service.status)
                            Text(service.status.rawValue.capitalized)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()

                    Divider()

                    // Log content
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                if logs.isEmpty {
                                    emptyStateView
                                } else {
                                    ForEach(logs) { entry in
                                        LogEntryView(entry: entry)
                                            .id(entry.id)
                                    }
                                }
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.system(.body, design: .monospaced))
                        .background(Color(nsColor: .textBackgroundColor))
                        .onChange(of: logs.count) { _ in
                            if autoScroll, let lastId = logs.last?.id {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    proxy.scrollTo(lastId, anchor: .bottom)
                                }
                            }
                        }
                    }

                    Divider()

                    // Footer
                    HStack {
                        Toggle("Auto-scroll", isOn: $autoScroll)
                            .toggleStyle(.checkbox)

                        Spacer()

                        Text("\(logs.count) entries")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Button("Copy All") {
                            copyAllLogs(service)
                        }
                        .disabled(logs.isEmpty)

                        Button("Clear") {
                            appState.clearLogs(for: serviceId)
                        }
                        .disabled(logs.isEmpty)
                    }
                    .padding()
                }
            } else {
                VStack {
                    Text("Service not found")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 500, minHeight: 300)
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("No logs yet")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Logs will appear here when the service runs")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 60)
    }

    private func copyAllLogs(_ service: Service) {
        let logText = logs.map { entry in
            "\(entry.formattedTimestamp) \(entry.message)"
        }.joined(separator: "\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(logText, forType: .string)
    }
}
