import SwiftUI

/// Sheet for previewing and confirming a bulk environment import
struct BulkImportPreviewSheet: View {
    let preview: BulkImportPreview
    let onImport: ([BulkEnvironmentPreview]) -> Void
    let onCancel: () -> Void

    @State private var environmentPreviews: [BulkEnvironmentPreview]

    init(preview: BulkImportPreview, onImport: @escaping ([BulkEnvironmentPreview]) -> Void, onCancel: @escaping () -> Void) {
        self.preview = preview
        self.onImport = onImport
        self.onCancel = onCancel
        self._environmentPreviews = State(initialValue: preview.environmentPreviews)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Import Archive")
                    .font(.title2)
                    .fontWeight(.bold)

                HStack(spacing: 12) {
                    Label("\(preview.environmentPreviews.count) environments", systemImage: "folder.fill")
                        .font(.callout)
                        .foregroundColor(.secondary)

                    Text("Exported \(formattedDate)")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.bottom, 16)

            // Batch actions
            HStack(spacing: 12) {
                Button {
                    selectAll()
                } label: {
                    Text("Select All")
                        .font(.caption)
                }
                .buttonStyle(.link)

                Button {
                    deselectAll()
                } label: {
                    Text("Deselect All")
                        .font(.caption)
                }
                .buttonStyle(.link)

                Spacer()

                if hasAnyConflicts {
                    Button {
                        applySuggestedToAll()
                    } label: {
                        Label("Use suggested IPs for all", systemImage: "wand.and.stars")
                            .font(.caption)
                    }
                    .buttonStyle(.link)
                }
            }
            .padding(.bottom, 8)

            // Environment list
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(environmentPreviews.enumerated()), id: \.element.id) { index, envPreview in
                        EnvironmentRow(
                            preview: binding(for: index),
                            onToggleSelected: { toggleSelection(at: index) }
                        )

                        if index < environmentPreviews.count - 1 {
                            Divider()
                                .padding(.leading, 48)
                        }
                    }
                }
            }
            .frame(maxHeight: 400)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )

            // Summary
            HStack {
                let selectedCount = environmentPreviews.filter { $0.isSelected }.count
                Text("\(selectedCount) of \(environmentPreviews.count) selected for import")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                if hasEmptyNames {
                    Label("Empty names", systemImage: "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                } else if conflictCount > 0 {
                    Label("\(conflictCount) with conflicts", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            .padding(.top, 8)

            // Footer buttons
            HStack {
                Spacer()

                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    onImport(environmentPreviews)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.down")
                        Text("Import \(selectedCount) Environment\(selectedCount == 1 ? "" : "s")")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(selectedCount == 0 || hasEmptyNames)
            }
            .padding(.top, 20)
        }
        .padding(24)
        .frame(width: 600, height: 580)
    }

    // MARK: - Computed Properties

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: preview.exportedAt)
    }

    private var hasAnyConflicts: Bool {
        environmentPreviews.contains { $0.preview.hasIPConflicts || $0.preview.hasNameConflict }
    }

    private var conflictCount: Int {
        environmentPreviews.filter { $0.isSelected && ($0.preview.hasIPConflicts || $0.preview.hasNameConflict) }.count
    }

    private var hasEmptyNames: Bool {
        environmentPreviews.contains { $0.isSelected && $0.editedName.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private var selectedCount: Int {
        environmentPreviews.filter { $0.isSelected }.count
    }

    // MARK: - Helpers

    private func binding(for index: Int) -> Binding<BulkEnvironmentPreview> {
        Binding(
            get: { environmentPreviews[index] },
            set: { environmentPreviews[index] = $0 }
        )
    }

    private func toggleSelection(at index: Int) {
        environmentPreviews[index].isSelected.toggle()
    }

    private func selectAll() {
        for index in environmentPreviews.indices {
            environmentPreviews[index].isSelected = true
        }
    }

    private func deselectAll() {
        for index in environmentPreviews.indices {
            environmentPreviews[index].isSelected = false
        }
    }

    private func applySuggestedToAll() {
        for index in environmentPreviews.indices {
            environmentPreviews[index].useSuggestedIPs = true
            environmentPreviews[index].editedName = environmentPreviews[index].preview.suggestedName
        }
    }
}

// MARK: - Environment Row

private struct EnvironmentRow: View {
    @Binding var preview: BulkEnvironmentPreview
    let onToggleSelected: () -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main row
            HStack(spacing: 12) {
                // Checkbox
                Button {
                    onToggleSelected()
                } label: {
                    Image(systemName: preview.isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundColor(preview.isSelected ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)

                // Environment info
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        // Editable name field
                        TextField("Name", text: $preview.editedName)
                            .textFieldStyle(.plain)
                            .font(.body.weight(.medium))
                            .frame(maxWidth: 200)

                        // Conflict indicators
                        if preview.preview.hasNameConflict {
                            ConflictBadge(text: "Name", icon: "exclamationmark.triangle.fill")
                        }
                        if preview.preview.hasIPConflicts {
                            ConflictBadge(text: "IP", icon: "exclamationmark.triangle.fill")
                        }
                        if preview.hasInterImportConflict {
                            ConflictBadge(text: "Archive", icon: "doc.on.doc.fill")
                        }
                    }

                    HStack(spacing: 8) {
                        // Interface summary
                        Text(interfaceSummary)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        // Services count
                        Text("\(preview.preview.services.count) service\(preview.preview.services.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Use suggested toggle (only show if has conflicts)
                if preview.preview.hasIPConflicts {
                    Toggle("Suggested IPs", isOn: $preview.useSuggestedIPs)
                        .toggleStyle(.checkbox)
                        .font(.caption)
                        .labelsHidden()

                    Text("Use suggested")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Expand/collapse button
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .opacity(preview.isSelected ? 1.0 : 0.5)

            // Expanded details
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    // Interfaces
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Interfaces")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)

                        ForEach(Array(displayInterfaces.enumerated()), id: \.offset) { index, interface in
                            HStack(spacing: 8) {
                                let varName = index == 0 ? "$IP" : "$IP\(index + 1)"
                                Text(varName)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(width: 35, alignment: .leading)

                                Text(interface.ip)
                                    .font(.system(.caption, design: .monospaced))

                                if let domain = interface.domain, !domain.isEmpty {
                                    Text("→ \(domain)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                // Show original if different
                                let original = preview.preview.originalInterfaces[safe: index]?.ip ?? ""
                                if preview.useSuggestedIPs && original != interface.ip {
                                    Text("(was \(original))")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                    }

                    // Services
                    if !preview.preview.services.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Services")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)

                            ForEach(Array(preview.preview.services.enumerated()), id: \.offset) { _, service in
                                HStack(spacing: 8) {
                                    Image(systemName: service.isEnabled ? "checkmark.circle.fill" : "circle")
                                        .font(.caption)
                                        .foregroundColor(service.isEnabled ? .green : .secondary)

                                    Text(service.name)
                                        .font(.caption)

                                    Text("(\(service.ports))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 48)
                .padding(.bottom, 12)
            }
        }
    }

    private var interfaceSummary: String {
        let interfaces = displayInterfaces
        if interfaces.count == 1 {
            return interfaces[0].ip
        } else {
            return "\(interfaces.count) IPs"
        }
    }

    private var displayInterfaces: [Interface] {
        preview.useSuggestedIPs ? preview.preview.suggestedInterfaces : preview.preview.originalInterfaces
    }
}

// MARK: - Conflict Badge

private struct ConflictBadge: View {
    let text: String
    let icon: String

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .imageScale(.small)
            Text(text)
        }
        .font(.caption2)
        .foregroundColor(.orange)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.orange.opacity(0.15))
        .cornerRadius(4)
    }
}

// MARK: - Safe Array Access

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#Preview {
    BulkImportPreviewSheet(
        preview: BulkImportPreview(
            manifestVersion: "1.0",
            appVersion: "0.5.5",
            exportedAt: Date(),
            environmentPreviews: [
                BulkEnvironmentPreview(
                    filename: "Claymore-DEV.orbit.json",
                    preview: ImportPreview(
                        originalName: "Claymore-DEV",
                        originalInterfaces: [Interface(ip: "127.0.0.2"), Interface(ip: "127.0.0.3")],
                        services: [
                            ExportedService(from: Service(
                                name: "postgres",
                                ports: "5432",
                                command: "kubectl port-forward --address $IP svc/postgres 5432:5432"
                            )),
                            ExportedService(from: Service(
                                name: "redis",
                                ports: "6379",
                                command: "kubectl port-forward --address $IP2 svc/redis 6379:6379"
                            ))
                        ],
                        suggestedName: "Claymore-DEV (Imported)",
                        suggestedInterfaces: [Interface(ip: "127.0.0.4"), Interface(ip: "127.0.0.5")],
                        hasNameConflict: true,
                        hasIPConflicts: true,
                        conflictingIPs: ["127.0.0.2"]
                    )
                ),
                BulkEnvironmentPreview(
                    filename: "Meera-PROD.orbit.json",
                    preview: ImportPreview(
                        originalName: "Meera-PROD",
                        originalInterfaces: [Interface(ip: "127.0.0.10", domain: "*.meera-prod")],
                        services: [
                            ExportedService(from: Service(
                                name: "api",
                                ports: "8080",
                                command: "kubectl port-forward --address $IP svc/api 8080:8080"
                            ))
                        ],
                        suggestedName: "Meera-PROD",
                        suggestedInterfaces: [Interface(ip: "127.0.0.10", domain: "*.meera-prod")],
                        hasNameConflict: false,
                        hasIPConflicts: false,
                        conflictingIPs: []
                    )
                )
            ]
        ),
        onImport: { _ in },
        onCancel: {}
    )
}
