import Foundation

/// Represents a development environment configuration
struct DevEnvironment: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var interfaces: [String]    // IP addresses, e.g., ["127.0.0.2", "127.0.0.3"]
    var services: [Service]
    var order: Int

    // MARK: - Runtime State (not persisted)

    var isEnabled: Bool = false
    var isTransitioning: Bool = false

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, name, interfaces, services, order
    }

    init(
        id: UUID = UUID(),
        name: String,
        interfaces: [String] = ["127.0.0.2"],
        services: [Service] = [],
        order: Int = 0
    ) {
        self.id = id
        self.name = name
        self.interfaces = interfaces
        self.services = services
        self.order = order
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        interfaces = try container.decode([String].self, forKey: .interfaces)
        services = try container.decode([Service].self, forKey: .services)
        order = try container.decode(Int.self, forKey: .order)
        // Runtime properties get default values
    }

    // MARK: - Equatable (only compare persisted properties)

    static func == (lhs: DevEnvironment, rhs: DevEnvironment) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.interfaces == rhs.interfaces &&
        lhs.services == rhs.services &&
        lhs.order == rhs.order
    }

    // MARK: - Computed Properties

    /// Aggregate status based on all services
    var aggregateStatus: ServiceStatus {
        let statuses = services.filter { $0.isEnabled }.map { $0.status }

        if statuses.isEmpty { return .stopped }
        if statuses.contains(.failed) { return .failed }
        if statuses.contains(.starting) { return .starting }
        if statuses.contains(.stopping) { return .stopping }
        if statuses.allSatisfy({ $0 == .running }) { return .running }
        if statuses.allSatisfy({ $0 == .stopped }) { return .stopped }

        return .running // Mixed state defaults to running
    }

    /// Whether any service is currently running
    var hasRunningServices: Bool {
        services.contains { $0.status == .running || $0.status == .starting }
    }

    /// Services sorted by order
    var sortedServices: [Service] {
        services.sorted { $0.order < $1.order }
    }

    /// Variable names for each interface ($IP, $IP2, $IP3, etc.)
    func variableName(for index: Int) -> String {
        index == 0 ? "$IP" : "$IP\(index + 1)"
    }

    /// All available variable names for hint display
    var availableVariables: [String] {
        interfaces.indices.map { variableName(for: $0) }
    }
}
