import Foundation

/// Resolves $IP variables in commands with actual IP addresses
enum VariableResolver {
    /// Resolve all $IP variables in a command string
    /// - Parameters:
    ///   - command: Command string containing $IP, $IP2, $IP3, etc.
    ///   - interfaces: Array of Interface objects to substitute
    /// - Returns: Command with variables replaced by actual IPs
    static func resolve(_ command: String, interfaces: [Interface]) -> String {
        var result = command

        // Replace variables in reverse order to handle $IP10 before $IP1
        for (index, interface) in interfaces.enumerated().reversed() {
            let variable = index == 0 ? "$IP" : "$IP\(index + 1)"
            result = result.replacingOccurrences(of: variable, with: interface.ip)
        }

        return result
    }

    /// Extract all variable names used in a command
    /// - Parameter command: Command string to analyze
    /// - Returns: Set of variable names found (e.g., ["$IP", "$IP2"])
    static func extractVariables(from command: String) -> Set<String> {
        var variables = Set<String>()

        // Match $IP followed by optional number
        let pattern = #"\$IP(\d*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return variables
        }

        let range = NSRange(command.startIndex..., in: command)
        let matches = regex.matches(in: command, range: range)

        for match in matches {
            if let matchRange = Range(match.range, in: command) {
                variables.insert(String(command[matchRange]))
            }
        }

        return variables
    }

    /// Check if all variables in a command are available
    /// - Parameters:
    ///   - command: Command string to check
    ///   - interfaceCount: Number of available interfaces
    /// - Returns: Array of missing variable names
    static func findMissingVariables(in command: String, interfaceCount: Int) -> [String] {
        let usedVariables = extractVariables(from: command)
        var missingVariables: [String] = []

        for variable in usedVariables {
            let index: Int
            if variable == "$IP" {
                index = 0
            } else if let numStr = variable.dropFirst(3).description.isEmpty ? nil : Int(variable.dropFirst(3)),
                      numStr > 1 {
                index = numStr - 1
            } else {
                continue
            }

            if index >= interfaceCount {
                missingVariables.append(variable)
            }
        }

        return missingVariables.sorted()
    }
}
