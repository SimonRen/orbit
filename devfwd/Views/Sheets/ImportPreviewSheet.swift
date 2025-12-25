import SwiftUI

/// Sheet for previewing and confirming an environment import
struct ImportPreviewSheet: View {
    let preview: ImportPreview
    let onImport: (String, Bool) -> Void  // (name, useSuggestedIPs)
    let onCancel: () -> Void

    @State private var editedName: String = ""
    @State private var useSuggestedIPs: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Import Environment")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Review the environment configuration before importing.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 20)

            // Content
            VStack(alignment: .leading, spacing: 16) {
                // Environment Name
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Environment Name")
                            .font(.headline)

                        if preview.hasNameConflict {
                            Label("Name conflict", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }

                    HStack {
                        Image(systemName: "folder")
                            .foregroundColor(.secondary)
                        TextField("Environment Name", text: $editedName)
                            .textFieldStyle(.plain)
                    }
                    .padding(10)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)

                    if preview.hasNameConflict {
                        Text("An environment with this name already exists. The name has been adjusted.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Interfaces
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Interfaces")
                            .font(.headline)

                        if preview.hasIPConflicts {
                            Label("\(preview.conflictingIPs.count) conflict(s)", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }

                    VStack(spacing: 0) {
                        ForEach(Array(displayInterfaces.enumerated()), id: \.offset) { index, ip in
                            interfaceRow(index: index, ip: ip)

                            if index < displayInterfaces.count - 1 {
                                Divider()
                                    .padding(.leading, 50)
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    )

                    if preview.hasIPConflicts {
                        Toggle("Use suggested IPs to avoid conflicts", isOn: $useSuggestedIPs)
                            .font(.caption)
                            .toggleStyle(.checkbox)
                    }
                }

                // Services
                VStack(alignment: .leading, spacing: 6) {
                    Text("Services")
                        .font(.headline)

                    VStack(spacing: 0) {
                        ForEach(Array(preview.services.enumerated()), id: \.offset) { index, service in
                            serviceRow(service: service)

                            if index < preview.services.count - 1 {
                                Divider()
                                    .padding(.leading, 50)
                            }
                        }

                        if preview.services.isEmpty {
                            HStack {
                                Image(systemName: "tray")
                                    .foregroundColor(.secondary)
                                Text("No services configured")
                                    .foregroundColor(.secondary)
                            }
                            .padding(12)
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    )
                }
            }

            Spacer()

            // Footer buttons
            HStack {
                Spacer()

                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    onImport(editedName.trimmingCharacters(in: .whitespaces), useSuggestedIPs)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.down")
                        Text("Import")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(editedName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.top, 20)
        }
        .padding(24)
        .frame(width: 500, height: 550)
        .onAppear {
            editedName = preview.suggestedName
        }
    }

    private var displayInterfaces: [String] {
        useSuggestedIPs ? preview.suggestedInterfaces : preview.originalInterfaces
    }

    private func interfaceRow(index: Int, ip: String) -> some View {
        let variableName = index == 0 ? "$IP" : "$IP\(index + 1)"
        let isConflicting = preview.conflictingIPs.contains(preview.originalInterfaces[safe: index] ?? "")
        let originalIP = preview.originalInterfaces[safe: index] ?? ""

        return HStack(spacing: 12) {
            Text(variableName)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .leading)

            Text(ip)
                .font(.system(.body, design: .monospaced))

            if isConflicting && useSuggestedIPs && originalIP != ip {
                Text("(was \(originalIP))")
                    .font(.caption)
                    .foregroundColor(.orange)
            } else if isConflicting && !useSuggestedIPs {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(.orange)
                    .imageScale(.small)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func serviceRow(service: ExportedService) -> some View {
        HStack(spacing: 12) {
            Image(systemName: service.isEnabled ? "checkmark.circle.fill" : "circle")
                .foregroundColor(service.isEnabled ? .green : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(service.name)
                    .font(.body)
                Text("Ports: \(service.ports)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Safe Array Access

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#Preview {
    ImportPreviewSheet(
        preview: ImportPreview(
            originalName: "Claymore-DEV",
            originalInterfaces: ["127.0.0.2", "127.0.0.3"],
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
            suggestedInterfaces: ["127.0.0.4", "127.0.0.5"],
            hasNameConflict: true,
            hasIPConflicts: true,
            conflictingIPs: ["127.0.0.2"]
        ),
        onImport: { _, _ in },
        onCancel: {}
    )
}
