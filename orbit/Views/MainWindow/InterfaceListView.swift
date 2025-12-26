import SwiftUI

/// List of interface IP addresses with add/remove capability
struct InterfaceListView: View {
    @Binding var interfaces: [String]
    let isDisabled: Bool
    let allEnvironments: [DevEnvironment]
    let currentEnvironmentId: UUID

    @State private var validationErrors: [Int: String] = [:]

    private let validationService = ValidationService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack {
                Image(systemName: "network")
                    .foregroundColor(.secondary)
                Text("INTERFACE")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }

            // Interface rows
            ForEach(Array(interfaces.enumerated()), id: \.offset) { index, _ in
                InterfaceRowView(
                    index: index,
                    ipAddress: Binding(
                        get: { interfaces[index] },
                        set: { newValue in
                            interfaces[index] = newValue
                            validateIP(at: index, value: newValue)
                        }
                    ),
                    isDisabled: isDisabled,
                    canRemove: interfaces.count > 1,
                    onRemove: { removeInterface(at: index) },
                    validationError: validationErrors[index]
                )
            }

            // Add interface button
            if !isDisabled {
                Button(action: addInterface) {
                    HStack {
                        Image(systemName: "plus.circle")
                        Text("Add Interface")
                    }
                    .font(.callout)
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Actions

    private func addInterface() {
        let newIP = suggestNextIP()
        interfaces.append(newIP)
    }

    private func removeInterface(at index: Int) {
        guard interfaces.count > 1 else { return }
        interfaces.remove(at: index)
        validationErrors.removeValue(forKey: index)
        // Reindex validation errors
        var newErrors: [Int: String] = [:]
        for (key, value) in validationErrors {
            if key > index {
                newErrors[key - 1] = value
            } else {
                newErrors[key] = value
            }
        }
        validationErrors = newErrors
    }

    // MARK: - Validation

    private func validateIP(at index: Int, value: String) {
        // Format validation
        if case .failure(let error) = validationService.validateIP(value) {
            validationErrors[index] = error.localizedDescription
            return
        }

        // Uniqueness within this environment
        let otherIPs = interfaces.enumerated().filter { $0.offset != index }.map { $0.element }
        if otherIPs.contains(value) {
            validationErrors[index] = "IP already used in this environment"
            return
        }

        // Uniqueness across all environments
        if case .failure(let error) = validationService.validateIPUniqueness(
            value,
            in: allEnvironments,
            excludingEnvironmentId: currentEnvironmentId
        ) {
            validationErrors[index] = error.localizedDescription
            return
        }

        // Valid
        validationErrors.removeValue(forKey: index)
    }

    private func suggestNextIP() -> String {
        let usedIPs = Set(allEnvironments.flatMap { $0.interfaces })

        for i in 2...254 {
            let candidate = "127.0.0.\(i)"
            if !usedIPs.contains(candidate) && !interfaces.contains(candidate) {
                return candidate
            }
        }

        return "127.0.1.1"
    }
}

#Preview {
    InterfaceListView(
        interfaces: .constant(["127.0.0.2", "127.0.0.3"]),
        isDisabled: false,
        allEnvironments: [],
        currentEnvironmentId: UUID()
    )
    .padding()
    .frame(width: 400)
}
