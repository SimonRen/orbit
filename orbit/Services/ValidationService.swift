import Foundation

/// Validation error types
enum ValidationError: LocalizedError, Equatable {
    case emptyValue(field: String)
    case invalidIPFormat
    case ipNotInLoopbackRange
    case ipAlreadyInUse(ip: String, environmentName: String)
    case invalidPortFormat
    case portOutOfRange(port: Int)
    case duplicateEnvironmentName(name: String)

    var errorDescription: String? {
        switch self {
        case .emptyValue(let field):
            return "\(field) cannot be empty"
        case .invalidIPFormat:
            return "Invalid IP format. Use format: 127.x.x.x"
        case .ipNotInLoopbackRange:
            return "IP must be in loopback range (127.x.x.x)"
        case .ipAlreadyInUse(let ip, let envName):
            return "IP \(ip) is already used in '\(envName)'"
        case .invalidPortFormat:
            return "Invalid port format. Use comma-separated numbers (e.g., 80,443,8080)"
        case .portOutOfRange(let port):
            return "Port \(port) is out of valid range (1-65535)"
        case .duplicateEnvironmentName(let name):
            return "Environment '\(name)' already exists"
        }
    }
}

/// Validation result type
typealias ValidationResult = Result<Void, ValidationError>

/// Provides validation for user input
final class ValidationService {
    static let shared = ValidationService()

    private init() {}

    // MARK: - IP Validation

    /// Validates IP address format and loopback range
    /// - Parameter ip: IP address string to validate
    /// - Returns: ValidationResult indicating success or specific error
    func validateIP(_ ip: String) -> ValidationResult {
        let trimmed = ip.trimmingCharacters(in: .whitespaces)

        guard !trimmed.isEmpty else {
            return .failure(.emptyValue(field: "IP address"))
        }

        // Check format: 127.x.x.x where x is 0-255
        let pattern = #"^127\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: trimmed,
                range: NSRange(trimmed.startIndex..., in: trimmed)
              ) else {
            return .failure(.invalidIPFormat)
        }

        // Validate each octet is 0-255
        for i in 1...3 {
            guard let range = Range(match.range(at: i), in: trimmed),
                  let octet = Int(trimmed[range]),
                  octet >= 0 && octet <= 255 else {
                return .failure(.invalidIPFormat)
            }
        }

        return .success(())
    }

    /// Validates IP uniqueness across all environments
    /// - Parameters:
    ///   - ip: IP address to check
    ///   - environments: All environments to check against
    ///   - excludingEnvironmentId: Environment ID to exclude (for editing)
    /// - Returns: ValidationResult indicating success or conflict
    func validateIPUniqueness(
        _ ip: String,
        in environments: [DevEnvironment],
        excludingEnvironmentId: UUID? = nil
    ) -> ValidationResult {
        let trimmed = ip.trimmingCharacters(in: .whitespaces)

        for env in environments {
            // Skip the environment being edited
            if env.id == excludingEnvironmentId { continue }

            if env.interfaceIPs.contains(trimmed) {
                return .failure(.ipAlreadyInUse(ip: trimmed, environmentName: env.name))
            }
        }

        return .success(())
    }

    // MARK: - Port Validation

    /// Validates port format (comma-separated integers 1-65535)
    /// - Parameter ports: Port string to validate
    /// - Returns: ValidationResult indicating success or specific error
    func validatePorts(_ ports: String) -> ValidationResult {
        let trimmed = ports.trimmingCharacters(in: .whitespaces)

        guard !trimmed.isEmpty else {
            return .failure(.emptyValue(field: "Ports"))
        }

        let portStrings = trimmed.split(separator: ",")

        guard !portStrings.isEmpty else {
            return .failure(.invalidPortFormat)
        }

        for portString in portStrings {
            let portTrimmed = portString.trimmingCharacters(in: .whitespaces)

            guard let port = Int(portTrimmed) else {
                return .failure(.invalidPortFormat)
            }

            guard port >= 1 && port <= 65535 else {
                return .failure(.portOutOfRange(port: port))
            }
        }

        return .success(())
    }

    // MARK: - Environment Name Validation

    /// Validates environment name is non-empty and unique
    /// - Parameters:
    ///   - name: Environment name to validate
    ///   - environments: All environments to check against
    ///   - excludingEnvironmentId: Environment ID to exclude (for editing)
    /// - Returns: ValidationResult indicating success or specific error
    func validateEnvironmentName(
        _ name: String,
        in environments: [DevEnvironment],
        excludingEnvironmentId: UUID? = nil
    ) -> ValidationResult {
        let trimmed = name.trimmingCharacters(in: .whitespaces)

        guard !trimmed.isEmpty else {
            return .failure(.emptyValue(field: "Environment name"))
        }

        // Case-insensitive uniqueness check
        let lowercasedName = trimmed.lowercased()

        for env in environments {
            // Skip the environment being edited
            if env.id == excludingEnvironmentId { continue }

            if env.name.lowercased() == lowercasedName {
                return .failure(.duplicateEnvironmentName(name: env.name))
            }
        }

        return .success(())
    }

    // MARK: - Service Validation

    /// Validates service name is non-empty
    /// - Parameter name: Service name to validate
    /// - Returns: ValidationResult
    func validateServiceName(_ name: String) -> ValidationResult {
        let trimmed = name.trimmingCharacters(in: .whitespaces)

        guard !trimmed.isEmpty else {
            return .failure(.emptyValue(field: "Service name"))
        }

        return .success(())
    }

    /// Validates service command is non-empty
    /// - Parameter command: Command string to validate
    /// - Returns: ValidationResult
    func validateCommand(_ command: String) -> ValidationResult {
        let trimmed = command.trimmingCharacters(in: .whitespaces)

        guard !trimmed.isEmpty else {
            return .failure(.emptyValue(field: "Command"))
        }

        return .success(())
    }

    // MARK: - Convenience Methods

    /// Validates all fields of a service
    func validateService(name: String, ports: String, command: String) -> [ValidationError] {
        var errors: [ValidationError] = []

        if case .failure(let error) = validateServiceName(name) {
            errors.append(error)
        }
        if case .failure(let error) = validatePorts(ports) {
            errors.append(error)
        }
        if case .failure(let error) = validateCommand(command) {
            errors.append(error)
        }

        return errors
    }

    /// Check if a service configuration is valid
    func isServiceValid(name: String, ports: String, command: String) -> Bool {
        validateService(name: name, ports: ports, command: command).isEmpty
    }
}
