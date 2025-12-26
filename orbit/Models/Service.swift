import Foundation

/// Represents a service configuration within an environment
struct Service: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var ports: String           // Comma-separated ports, e.g., "80,443,8080"
    var command: String         // Shell command with $IP variables
    var isEnabled: Bool
    var order: Int

    // MARK: - Runtime State (not persisted)

    var status: ServiceStatus = .stopped
    var restartCount: Int = 0
    var lastError: String?
    var logs: [LogEntry] = []

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, name, ports, command, isEnabled, order
    }

    init(
        id: UUID = UUID(),
        name: String,
        ports: String,
        command: String,
        isEnabled: Bool = true,
        order: Int = 0
    ) {
        self.id = id
        self.name = name
        self.ports = ports
        self.command = command
        self.isEnabled = isEnabled
        self.order = order
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        ports = try container.decode(String.self, forKey: .ports)
        command = try container.decode(String.self, forKey: .command)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        order = try container.decode(Int.self, forKey: .order)
        // Runtime properties get default values
    }

    // MARK: - Equatable (only compare persisted properties)

    static func == (lhs: Service, rhs: Service) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.ports == rhs.ports &&
        lhs.command == rhs.command &&
        lhs.isEnabled == rhs.isEnabled &&
        lhs.order == rhs.order
    }

    // MARK: - Computed Properties

    /// Array of individual port numbers
    var portList: [Int] {
        ports.split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }

    /// Display-friendly port string
    var portsDisplay: String {
        portList.map(String.init).joined(separator: ", ")
    }
}
