import XCTest
@testable import Orbit

final class OrbitTests: XCTestCase {

    // MARK: - ValidationService Tests

    func testValidIPFormat() {
        let validation = ValidationService.shared

        // Valid IPs
        XCTAssertNoThrow(try validation.validateIP("127.0.0.2").get())
        XCTAssertNoThrow(try validation.validateIP("127.0.0.255").get())
        XCTAssertNoThrow(try validation.validateIP("127.255.255.255").get())

        // Invalid IPs
        XCTAssertThrowsError(try validation.validateIP("192.168.1.1").get())
        XCTAssertThrowsError(try validation.validateIP("127.0.0").get())
        XCTAssertThrowsError(try validation.validateIP("not-an-ip").get())
        XCTAssertThrowsError(try validation.validateIP("").get())
    }

    func testValidPortFormat() {
        let validation = ValidationService.shared

        // Valid ports
        XCTAssertNoThrow(try validation.validatePorts("80").get())
        XCTAssertNoThrow(try validation.validatePorts("80,443").get())
        XCTAssertNoThrow(try validation.validatePorts("80, 443, 8080").get())

        // Invalid ports
        XCTAssertThrowsError(try validation.validatePorts("").get())
        XCTAssertThrowsError(try validation.validatePorts("abc").get())
        XCTAssertThrowsError(try validation.validatePorts("0").get())
        XCTAssertThrowsError(try validation.validatePorts("70000").get())
    }

    // MARK: - VariableResolver Tests

    func testVariableResolution() {
        let command = "kubectl port-forward svc/auth $IP:8080:8080"
        let interfaces = [Interface(ip: "127.0.0.2")]

        let resolved = VariableResolver.resolve(command, interfaces: interfaces)

        XCTAssertEqual(resolved, "kubectl port-forward svc/auth 127.0.0.2:8080:8080")
    }

    func testMultipleVariableResolution() {
        let command = "ssh -L $IP:3000:localhost:3000 -L $IP2:3001:localhost:3001"
        let interfaces = [Interface(ip: "127.0.0.2"), Interface(ip: "127.0.0.3")]

        let resolved = VariableResolver.resolve(command, interfaces: interfaces)

        XCTAssertEqual(resolved, "ssh -L 127.0.0.2:3000:localhost:3000 -L 127.0.0.3:3001:localhost:3001")
    }

    // MARK: - Model Tests

    func testServiceCodable() throws {
        let service = Service(
            name: "test-service",
            ports: "8080",
            command: "echo hello"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(service)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Service.self, from: data)

        XCTAssertEqual(decoded.name, service.name)
        XCTAssertEqual(decoded.ports, service.ports)
        XCTAssertEqual(decoded.command, service.command)
        // Runtime properties should be default values
        XCTAssertEqual(decoded.status, .stopped)
        XCTAssertEqual(decoded.restartCount, 0)
    }

    func testEnvironmentCodable() throws {
        let environment = DevEnvironment(
            name: "Test Env",
            interfaces: [Interface(ip: "127.0.0.2")],
            services: [
                Service(name: "svc1", ports: "80", command: "cmd1")
            ]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(environment)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DevEnvironment.self, from: data)

        XCTAssertEqual(decoded.name, environment.name)
        XCTAssertEqual(decoded.interfaces, environment.interfaces)
        XCTAssertEqual(decoded.services.count, 1)
        // Runtime property should be default
        XCTAssertFalse(decoded.isEnabled)
    }

    func testEnvironmentMigrationFromOldFormat() throws {
        // Simulate old format JSON with string array interfaces
        let oldFormatJSON = """
        {
            "id": "12345678-1234-1234-1234-123456789012",
            "name": "Old Env",
            "interfaces": ["127.0.0.2", "127.0.0.3"],
            "services": [],
            "order": 0
        }
        """

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DevEnvironment.self, from: oldFormatJSON.data(using: .utf8)!)

        XCTAssertEqual(decoded.name, "Old Env")
        XCTAssertEqual(decoded.interfaces.count, 2)
        XCTAssertEqual(decoded.interfaces[0].ip, "127.0.0.2")
        XCTAssertEqual(decoded.interfaces[1].ip, "127.0.0.3")
        XCTAssertNil(decoded.interfaces[0].domain)
        XCTAssertNil(decoded.interfaces[1].domain)
    }

    func testInterfaceWithDomain() throws {
        let interface = Interface(ip: "127.0.0.2", domain: "*.meera-dev")

        let encoder = JSONEncoder()
        let data = try encoder.encode(interface)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Interface.self, from: data)

        XCTAssertEqual(decoded.ip, "127.0.0.2")
        XCTAssertEqual(decoded.domain, "*.meera-dev")
    }

    func testExportBackwardCompatibility_NoDomains() throws {
        // When no domains are set, export should use legacy [String] format
        let env = DevEnvironment(
            name: "Test",
            interfaces: [Interface(ip: "127.0.0.2"), Interface(ip: "127.0.0.3")],
            services: []
        )
        let exported = ExportedEnvironment(from: env)

        let encoder = JSONEncoder()
        let data = try encoder.encode(exported)
        let json = String(data: data, encoding: .utf8)!

        // Should contain string array format, not object format
        XCTAssertTrue(json.contains("\"interfaces\":[\"127.0.0.2\",\"127.0.0.3\"]") ||
                      json.contains("\"interfaces\" : [\"127.0.0.2\", \"127.0.0.3\"]") ||
                      json.contains("\"interfaces\":[\"127.0.0.2\",\"127.0.0.3\"]"))
        XCTAssertFalse(json.contains("\"ip\""))
    }

    func testExportWithDomains_UsesNewFormat() throws {
        // When domains are set, export should use new Interface format
        let env = DevEnvironment(
            name: "Test",
            interfaces: [Interface(ip: "127.0.0.2", domain: "*.test")],
            services: []
        )
        let exported = ExportedEnvironment(from: env)

        let encoder = JSONEncoder()
        let data = try encoder.encode(exported)
        let json = String(data: data, encoding: .utf8)!

        // Should contain object format with ip and domain
        XCTAssertTrue(json.contains("\"ip\""))
        XCTAssertTrue(json.contains("\"domain\""))
        XCTAssertTrue(json.contains("*.test"))
    }

    // MARK: - History Snapshot Tests

    func testHistorySnapshotCreation() {
        let env = DevEnvironment(
            name: "Test Env",
            interfaces: [Interface(ip: "127.0.0.2")],
            services: [Service(name: "svc1", ports: "80", command: "cmd1")]
        )

        let snapshot = HistorySnapshot(from: env)

        XCTAssertEqual(snapshot.schemaVersion, SnapshotSchema.current)
        XCTAssertEqual(snapshot.data.name, "Test Env")
        XCTAssertEqual(snapshot.data.interfaces.count, 1)
        XCTAssertEqual(snapshot.data.interfaces[0].ip, "127.0.0.2")
        XCTAssertEqual(snapshot.data.services.count, 1)
        XCTAssertEqual(snapshot.data.services[0].name, "svc1")
    }

    func testHistorySnapshotCodable() throws {
        let env = DevEnvironment(
            name: "Test Env",
            interfaces: [Interface(ip: "127.0.0.2", domain: "*.test")],
            services: [Service(name: "svc1", ports: "80", command: "cmd1")]
        )

        let snapshot = HistorySnapshot(from: env)

        let encoder = JSONEncoder()
        let data = try encoder.encode(snapshot)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(HistorySnapshot.self, from: data)

        XCTAssertEqual(decoded.schemaVersion, snapshot.schemaVersion)
        XCTAssertEqual(decoded.data.name, snapshot.data.name)
        XCTAssertEqual(decoded.data.interfaces, snapshot.data.interfaces)
        XCTAssertEqual(decoded.data.services.count, snapshot.data.services.count)
    }

    func testHistoryMigratedData() {
        let env = DevEnvironment(
            name: "Test Env",
            interfaces: [Interface(ip: "127.0.0.2")],
            services: []
        )

        let snapshot = HistorySnapshot(from: env)
        let migrated = snapshot.migratedData()

        // Currently v1, no migration needed
        XCTAssertEqual(migrated.name, snapshot.data.name)
        XCTAssertEqual(migrated.interfaces, snapshot.data.interfaces)
        XCTAssertEqual(migrated.services, snapshot.data.services)
    }

    func testEnvironmentWithHistoryCodable() throws {
        var env = DevEnvironment(
            name: "Test Env",
            interfaces: [Interface(ip: "127.0.0.2")],
            services: []
        )

        // Add some history
        let oldEnv = DevEnvironment(
            name: "Old Name",
            interfaces: [Interface(ip: "127.0.0.3")],
            services: []
        )
        env.history = [HistorySnapshot(from: oldEnv)]

        let encoder = JSONEncoder()
        let data = try encoder.encode(env)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DevEnvironment.self, from: data)

        XCTAssertEqual(decoded.name, "Test Env")
        XCTAssertEqual(decoded.history.count, 1)
        XCTAssertEqual(decoded.history[0].data.name, "Old Name")
        XCTAssertEqual(decoded.history[0].data.interfaces[0].ip, "127.0.0.3")
    }

    func testEnvironmentBackwardCompatibilityNoHistory() throws {
        // Simulate old format JSON without history field
        let oldFormatJSON = """
        {
            "id": "12345678-1234-1234-1234-123456789012",
            "name": "Old Env",
            "interfaces": [{"ip": "127.0.0.2"}],
            "services": [],
            "order": 0
        }
        """

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DevEnvironment.self, from: oldFormatJSON.data(using: .utf8)!)

        XCTAssertEqual(decoded.name, "Old Env")
        XCTAssertEqual(decoded.history.count, 0)  // Should default to empty
    }

    func testEnvironmentEqualityExcludesHistory() {
        var env1 = DevEnvironment(
            id: UUID(),
            name: "Test",
            interfaces: [Interface(ip: "127.0.0.2")],
            services: []
        )

        var env2 = env1  // Copy
        env2.history = [HistorySnapshot(from: env1)]

        // Despite different history, environments should be equal
        // (core content is the same)
        XCTAssertEqual(env1, env2)
    }
}

// MARK: - AppState History Tests

@MainActor
final class AppStateHistoryTests: XCTestCase {

    func testUpdateEnvironmentCreatesSnapshot() {
        let appState = AppState()
        appState.environments = [
            DevEnvironment(
                name: "Original",
                interfaces: [Interface(ip: "127.0.0.2")],
                services: []
            )
        ]

        let envId = appState.environments[0].id
        var updatedEnv = appState.environments[0]
        updatedEnv.name = "Updated"

        appState.updateEnvironment(updatedEnv)

        XCTAssertEqual(appState.environments[0].name, "Updated")
        XCTAssertEqual(appState.environments[0].history.count, 1)
        XCTAssertEqual(appState.environments[0].history[0].data.name, "Original")
        XCTAssertEqual(appState.environments[0].history[0].schemaVersion, SnapshotSchema.current)
    }

    func testUpdateEnvironmentPreservesHistoryWhenNoChange() {
        let appState = AppState()
        var env = DevEnvironment(
            name: "Test",
            interfaces: [Interface(ip: "127.0.0.2")],
            services: []
        )
        // Pre-populate some history
        let existingSnapshot = HistorySnapshot(from: DevEnvironment(name: "OldState", interfaces: [], services: []))
        env.history = [existingSnapshot]
        appState.environments = [env]

        // Update with same content
        appState.updateEnvironment(env)

        // History should be preserved, not doubled
        XCTAssertEqual(appState.environments[0].history.count, 1)
        XCTAssertEqual(appState.environments[0].history[0].data.name, "OldState")
    }

    func testHistoryMaxLimit() {
        let appState = AppState()
        appState.environments = [
            DevEnvironment(
                name: "Env0",
                interfaces: [Interface(ip: "127.0.0.2")],
                services: []
            )
        ]

        // Make 12 updates to exceed max limit of 10
        for i in 1...12 {
            var updatedEnv = appState.environments[0]
            updatedEnv.name = "Env\(i)"
            appState.updateEnvironment(updatedEnv)
        }

        // Should have exactly 10 history entries (max)
        XCTAssertEqual(appState.environments[0].history.count, 10)
        XCTAssertEqual(appState.environments[0].name, "Env12")

        // Most recent history entry should be Env11 (the previous state)
        XCTAssertEqual(appState.environments[0].history[0].data.name, "Env11")

        // Oldest entry should be Env2 (Env0 and Env1 got dropped)
        XCTAssertEqual(appState.environments[0].history[9].data.name, "Env2")
    }

    func testRestoreFromHistory() {
        let appState = AppState()
        appState.environments = [
            DevEnvironment(
                name: "Original",
                interfaces: [Interface(ip: "127.0.0.2")],
                services: [Service(name: "svc1", ports: "80", command: "cmd1")]
            )
        ]

        let envId = appState.environments[0].id

        // Make an update
        var updatedEnv = appState.environments[0]
        updatedEnv.name = "Updated"
        updatedEnv.interfaces = [Interface(ip: "127.0.0.3")]
        appState.updateEnvironment(updatedEnv)

        // Verify update worked
        XCTAssertEqual(appState.environments[0].name, "Updated")
        XCTAssertEqual(appState.environments[0].interfaces[0].ip, "127.0.0.3")
        XCTAssertEqual(appState.environments[0].history.count, 1)

        // Restore from history
        appState.restoreFromHistory(envId, snapshotIndex: 0)

        // Should be back to original
        XCTAssertEqual(appState.environments[0].name, "Original")
        XCTAssertEqual(appState.environments[0].interfaces[0].ip, "127.0.0.2")
        XCTAssertEqual(appState.environments[0].services.count, 1)

        // Current state should now be in history (restore is reversible)
        XCTAssertEqual(appState.environments[0].history.count, 2)
        XCTAssertEqual(appState.environments[0].history[0].data.name, "Updated")
    }

    func testRestoreFromHistoryPreservesId() {
        let appState = AppState()
        let originalId = UUID()
        appState.environments = [
            DevEnvironment(
                id: originalId,
                name: "Test",
                interfaces: [Interface(ip: "127.0.0.2")],
                services: [],
                order: 5
            )
        ]

        // Make update and restore
        var updatedEnv = appState.environments[0]
        updatedEnv.name = "Changed"
        appState.updateEnvironment(updatedEnv)
        appState.restoreFromHistory(originalId, snapshotIndex: 0)

        // ID and order should be preserved
        XCTAssertEqual(appState.environments[0].id, originalId)
        XCTAssertEqual(appState.environments[0].order, 5)
    }

    func testRestoreFromHistoryInvalidIndex() {
        let appState = AppState()
        appState.environments = [
            DevEnvironment(name: "Test", interfaces: [], services: [])
        ]

        let envId = appState.environments[0].id

        // Try to restore with no history
        appState.restoreFromHistory(envId, snapshotIndex: 0)

        // Should be unchanged
        XCTAssertEqual(appState.environments[0].name, "Test")
        XCTAssertEqual(appState.environments[0].history.count, 0)

        // Try with negative index
        appState.restoreFromHistory(envId, snapshotIndex: -1)
        XCTAssertEqual(appState.environments[0].name, "Test")
    }

    func testRestoreKeepsMaxHistory() {
        let appState = AppState()
        appState.environments = [
            DevEnvironment(name: "Env0", interfaces: [], services: [])
        ]

        let envId = appState.environments[0].id

        // Make 10 updates to fill history
        for i in 1...10 {
            var env = appState.environments[0]
            env.name = "Env\(i)"
            appState.updateEnvironment(env)
        }

        XCTAssertEqual(appState.environments[0].history.count, 10)

        // Restore from oldest entry
        appState.restoreFromHistory(envId, snapshotIndex: 9)

        // Should still have max 10 entries
        XCTAssertEqual(appState.environments[0].history.count, 10)
    }
}
