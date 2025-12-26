import SwiftUI
import AppKit

/// Sheet for viewing service logs
struct LogViewerSheet: View {
    let service: Service
    let onClear: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var autoScroll = true

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Logs")
                        .font(.headline)
                    Text(service.name)
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

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .imageScale(.large)
                }
                .buttonStyle(.plain)
                .padding(.leading, 16)
            }
            .padding()

            Divider()

            // Log content
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if service.logs.isEmpty {
                            emptyStateView
                        } else {
                            ForEach(service.logs) { entry in
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
                .onChange(of: service.logs.count) { _ in
                    if autoScroll, let lastId = service.logs.last?.id {
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

                Text("\(service.logs.count) entries")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button("Copy All") {
                    copyAllLogs()
                }
                .disabled(service.logs.isEmpty)

                Button("Clear") {
                    onClear()
                }
                .disabled(service.logs.isEmpty)
            }
            .padding()
        }
        .frame(minWidth: 500, idealWidth: 700, maxWidth: .infinity,
               minHeight: 300, idealHeight: 500, maxHeight: .infinity)
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

    private func copyAllLogs() {
        let logText = service.logs.map { entry in
            "\(entry.formattedTimestamp) \(entry.message)"
        }.joined(separator: "\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(logText, forType: .string)
    }
}

/// Individual log entry view
struct LogEntryView: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(entry.formattedTimestamp)
                .foregroundColor(.secondary)

            Text(entry.message)
                .foregroundColor(entry.stream == .stderr ? .red : .primary)
                .textSelection(.enabled)
        }
        .font(.system(.caption, design: .monospaced))
    }
}

#Preview {
    LogViewerSheet(
        service: {
            var s = Service(
                name: "auth-service-v2",
                ports: "8080",
                command: "kubectl port-forward"
            )
            s.status = .running
            s.logs = [
                LogEntry(message: "Starting service...", stream: .stdout),
                LogEntry(message: "Connecting to cluster...", stream: .stdout),
                LogEntry(message: "Warning: deprecated API", stream: .stderr),
                LogEntry(message: "Port forwarding established on 127.0.0.2:8080", stream: .stdout),
                LogEntry(message: "Ready to accept connections", stream: .stdout),
            ]
            return s
        }(),
        onClear: {}
    )
}
