import SwiftUI

/// Sheet for adding a new service to an environment
struct AddServiceSheet: View {
    let availableVariables: [String]
    let onSave: (Service) -> Void
    let onCancel: () -> Void

    @State private var serviceName: String = ""
    @State private var ports: String = ""
    @State private var command: String = ""

    @State private var nameError: String?
    @State private var portsError: String?
    @State private var commandError: String?

    private let validationService = ValidationService.shared

    private var isValid: Bool {
        !serviceName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !ports.trimmingCharacters(in: .whitespaces).isEmpty &&
        !command.trimmingCharacters(in: .whitespaces).isEmpty &&
        nameError == nil &&
        portsError == nil &&
        commandError == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Add Service")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Configure the service parameters for your environment.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 20)

            // Form fields
            VStack(alignment: .leading, spacing: 16) {
                // Service Name
                VStack(alignment: .leading, spacing: 6) {
                    Text("Service Name")
                        .font(.headline)

                    HStack {
                        Image(systemName: "server.rack")
                            .foregroundColor(.secondary)
                        TextField("e.g. payment-gateway-api", text: $serviceName)
                            .textFieldStyle(.plain)
                    }
                    .padding(10)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                    .onChange(of: serviceName) { _ in validateName() }

                    if let error = nameError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                // Ports
                VStack(alignment: .leading, spacing: 6) {
                    Text("Ports")
                        .font(.headline)

                    HStack {
                        Image(systemName: "network")
                            .foregroundColor(.secondary)
                        TextField("80,443,8080", text: $ports)
                            .textFieldStyle(.plain)
                    }
                    .padding(10)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                    .onChange(of: ports) { _ in validatePorts() }

                    if let error = portsError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                // Running Command
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Running Command")
                            .font(.headline)
                        Spacer()
                        Text("bash")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(4)
                    }

                    TextEditor(text: $command)
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(minHeight: 100)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(8)
                        .onChange(of: command) { _ in validateCommand() }

                    if let error = commandError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                // Variable hint box
                if !availableVariables.isEmpty {
                    variableHintBox
                }

                // Sample commands
                sampleCommandsSection
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
                    saveService()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.down")
                        Text("Save Service")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 20)
        }
        .padding(24)
        .frame(width: 600, height: 700)
    }

    private var variableHintBox: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Available Variables")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                ForEach(availableVariables, id: \.self) { variable in
                    Text(variable)
                        .font(.system(.caption, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(4)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private var sampleCommandsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Example Commands")
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(spacing: 6) {
                SampleCommandRow(
                    title: "Kubernetes Port Forward",
                    command: "kubectl port-forward --address $IP svc/my-service 5432:5432 --context my-cluster"
                )

                SampleCommandRow(
                    title: "Cloudflare Tunnel",
                    command: "cloudflared access tcp --hostname $IP --url my-tunnel.example.com 8080"
                )

                SampleCommandRow(
                    title: "SSH Tunnel",
                    command: "ssh -N -L $IP:3306:localhost:3306 user@bastion.example.com"
                )
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Validation

    private func validateName() {
        if case .failure(let error) = validationService.validateServiceName(serviceName) {
            nameError = error.localizedDescription
        } else {
            nameError = nil
        }
    }

    private func validatePorts() {
        let trimmed = ports.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            portsError = nil
            return
        }

        if case .failure(let error) = validationService.validatePorts(ports) {
            portsError = error.localizedDescription
        } else {
            portsError = nil
        }
    }

    private func validateCommand() {
        if case .failure(let error) = validationService.validateCommand(command) {
            commandError = error.localizedDescription
        } else {
            commandError = nil
        }
    }

    private func saveService() {
        let service = Service(
            name: serviceName.trimmingCharacters(in: .whitespaces),
            ports: ports.trimmingCharacters(in: .whitespaces),
            command: command.trimmingCharacters(in: .whitespaces)
        )
        onSave(service)
    }
}

/// Row displaying a sample command with copy button
struct SampleCommandRow: View {
    let title: String
    let command: String
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(verbatim: command)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
            }

            Spacer(minLength: 30)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    copied = false
                }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .foregroundColor(copied ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .help("Copy to clipboard")
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    AddServiceSheet(
        availableVariables: ["$IP", "$IP2"],
        onSave: { _ in },
        onCancel: {}
    )
}
