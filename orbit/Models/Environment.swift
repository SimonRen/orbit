import Foundation

/// Represents an interface with IP address and optional domain alias
struct Interface: Codable, Equatable {
    var ip: String
    var domain: String?  // Optional: e.g., "*.meera-dev"

    init(ip: String, domain: String? = nil) {
        self.ip = ip
        self.domain = domain
    }
}

// MARK: - History Snapshots

/// Schema version for history snapshots - bump when snapshot data structure changes
enum SnapshotSchema {
    static let current = 1
}

/// The actual snapshot content (versioned separately from container)
struct SnapshotData: Codable, Equatable {
    let name: String
    let interfaces: [Interface]
    let services: [Service]
}

/// Versioned snapshot data - stores environment state at a point in time
struct HistorySnapshot: Codable, Equatable {
    let schemaVersion: Int
    let timestamp: Date
    let data: SnapshotData

    init(from environment: DevEnvironment) {
        self.schemaVersion = SnapshotSchema.current
        self.timestamp = Date()
        self.data = SnapshotData(
            name: environment.name,
            interfaces: environment.interfaces,
            services: environment.services
        )
    }

    /// Migrate snapshot data to current schema if needed
    func migratedData() -> SnapshotData {
        // Currently at v1, no migration needed
        // Future: add switch on schemaVersion for migrations
        return data
    }
}

/// Represents a development environment configuration
struct DevEnvironment: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var interfaces: [Interface]
    var services: [Service]
    var order: Int
    var history: [HistorySnapshot] = []  // Max 10, newest first

    // MARK: - Runtime State (not persisted)

    var isEnabled: Bool = false
    var isTransitioning: Bool = false

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, name, interfaces, services, order, history
    }

    init(
        id: UUID = UUID(),
        name: String,
        interfaces: [Interface] = [Interface(ip: "127.0.0.2")],
        services: [Service] = [],
        order: Int = 0,
        history: [HistorySnapshot] = []
    ) {
        self.id = id
        self.name = name
        self.interfaces = interfaces
        self.services = services
        self.order = order
        self.history = history
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)

        // Try new Interface format first, fall back to old [String] format for migration
        if let newInterfaces = try? container.decode([Interface].self, forKey: .interfaces) {
            interfaces = newInterfaces
        } else {
            let oldInterfaces = try container.decode([String].self, forKey: .interfaces)
            interfaces = oldInterfaces.map { Interface(ip: $0, domain: nil) }
        }

        services = try container.decode([Service].self, forKey: .services)
        order = try container.decode(Int.self, forKey: .order)

        // History is optional for backwards compatibility with existing configs
        history = (try? container.decode([HistorySnapshot].self, forKey: .history)) ?? []

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

    /// Extract just the IP addresses from interfaces
    var interfaceIPs: [String] {
        interfaces.map { $0.ip }
    }

    /// Generate AI-friendly markdown description for clipboard
    func copyableAIDescription() -> String {
        var lines: [String] = []

        // Header
        lines.append("## Environment: \(name)")
        lines.append("")

        // Check if any interface has a domain
        let hasDomains = interfaces.contains { $0.domain != nil && !$0.domain!.isEmpty }

        // Interfaces section
        lines.append("### Interfaces")
        if hasDomains {
            lines.append("*Loopback aliases on lo0. Domain patterns (e.g., `*.example`) are resolved via local DNS (dnsmasq) to the corresponding IP.*")
            lines.append("")
        }
        for (index, interface) in interfaces.enumerated() {
            let varName = variableName(for: index)
            if let domain = interface.domain, !domain.isEmpty {
                lines.append("- \(varName): `\(interface.ip)` → `\(domain)`")
            } else {
                lines.append("- \(varName): `\(interface.ip)`")
            }
        }
        lines.append("")

        // Services section (enabled services only)
        let enabledServices = sortedServices.filter { $0.isEnabled }
        lines.append("### Services")
        if enabledServices.isEmpty {
            lines.append("No enabled services.")
        } else {
            lines.append("| Service | Ports |")
            lines.append("|---------|-------|")

            for service in enabledServices {
                lines.append("| \(service.name) | \(service.ports) |")
            }
        }

        return lines.joined(separator: "\n")
    }
}
