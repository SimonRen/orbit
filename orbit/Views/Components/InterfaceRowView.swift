import SwiftUI

/// A single row for editing an interface IP address
struct InterfaceRowView: View {
    let index: Int
    @Binding var ipAddress: String
    let isDisabled: Bool
    let canRemove: Bool
    let onRemove: () -> Void
    let validationError: String?

    /// Variable name for this interface ($IP, $IP2, etc.)
    private var variableName: String {
        index == 0 ? "$IP" : "$IP\(index + 1)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                // Variable label
                Text(variableName)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 50, alignment: .leading)

                // IP input field
                TextField("127.0.0.x", text: $ipAddress)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isDisabled)
                    .frame(maxWidth: 150)

                // Remove button
                if canRemove {
                    Button(action: onRemove) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .imageScale(.medium)
                    }
                    .buttonStyle(.plain)
                    .disabled(isDisabled)
                    .help("Remove interface")
                }
            }

            // Validation error message
            if let error = validationError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.leading, 62) // Align with input field
            }
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        InterfaceRowView(
            index: 0,
            ipAddress: .constant("127.0.0.2"),
            isDisabled: false,
            canRemove: false,
            onRemove: {},
            validationError: nil
        )

        InterfaceRowView(
            index: 1,
            ipAddress: .constant("127.0.0.3"),
            isDisabled: false,
            canRemove: true,
            onRemove: {},
            validationError: nil
        )

        InterfaceRowView(
            index: 2,
            ipAddress: .constant("invalid"),
            isDisabled: false,
            canRemove: true,
            onRemove: {},
            validationError: "Invalid IP format"
        )

        InterfaceRowView(
            index: 0,
            ipAddress: .constant("127.0.0.2"),
            isDisabled: true,
            canRemove: false,
            onRemove: {},
            validationError: nil
        )
    }
    .padding()
    .frame(width: 400)
}
