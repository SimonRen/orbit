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

// MARK: - AppState CRUD Tests

@MainActor
final class AppStateCRUDTests: XCTestCase {

    /// Helper to create a clean AppState with no pre-loaded environments
    private func cleanAppState() -> AppState {
        return AppState(testMode: true)
    }

    func testCreateEnvironmentAssignsUniqueIP() {
        let appState = cleanAppState()
        let env1 = appState.createEnvironment()
        let env2 = appState.createEnvironment()

        XCTAssertNotEqual(env1.interfaces[0].ip, env2.interfaces[0].ip)
        XCTAssertEqual(appState.environments.count, 2)
    }

    func testCreateEnvironmentAssignsUniqueName() {
        let appState = cleanAppState()
        let env1 = appState.createEnvironment()
        let env2 = appState.createEnvironment()

        XCTAssertNotEqual(env1.name, env2.name)
    }

    func testDeleteEnvironmentCleansUpState() {
        let appState = cleanAppState()
        let env = appState.createEnvironment()
        let envId = env.id

        appState.selectedEnvironmentId = envId
        appState.deleteEnvironment(envId)

        XCTAssertTrue(appState.environments.isEmpty)
        // Selection should update
        XCTAssertNil(appState.selectedEnvironmentId)
    }

    func testDeleteEnvironmentUpdatesSelection() {
        let appState = cleanAppState()
        let env1 = appState.createEnvironment()
        let env2 = appState.createEnvironment()

        // Select env2, delete it - should fall back to env1
        appState.selectedEnvironmentId = env2.id
        appState.deleteEnvironment(env2.id)

        XCTAssertEqual(appState.selectedEnvironmentId, env1.id)
    }

    func testAddServiceUpdatesCache() {
        let appState = cleanAppState()
        let env = appState.createEnvironment()

        let service = Service(name: "test", ports: "8080", command: "echo hello")
        appState.addService(to: env.id, service: service)

        // Should be findable via cache
        XCTAssertNotNil(appState.service(for: service.id))
    }

    func testDeleteServiceCleansUpLogs() {
        let appState = cleanAppState()
        let env = appState.createEnvironment()

        let service = Service(name: "test", ports: "8080", command: "echo hello")
        appState.addService(to: env.id, service: service)

        // Simulate some logs
        appState.serviceLogs[service.id] = [
            LogEntry(message: "test log", stream: .stdout)
        ]

        appState.deleteService(from: env.id, serviceId: service.id)

        // Logs should be cleaned up
        XCTAssertNil(appState.serviceLogs[service.id])
        XCTAssertNil(appState.service(for: service.id))
    }

    func testMoveEnvironmentUpdatesOrder() {
        let appState = cleanAppState()
        let env1 = appState.createEnvironment()
        let env2 = appState.createEnvironment()
        let env3 = appState.createEnvironment()

        // Move env3 to position 0
        appState.moveEnvironment(from: IndexSet(integer: 2), to: 0)

        let sorted = appState.sortedEnvironments
        XCTAssertEqual(sorted[0].id, env3.id)
    }
}

// MARK: - AppState Log Management Tests

@MainActor
final class AppStateLogTests: XCTestCase {

    func testAppendLogStoresInSeparateStorage() {
        let appState = AppState()
        let env = appState.createEnvironment()
        let service = Service(name: "test", ports: "80", command: "echo hi")
        appState.addService(to: env.id, service: service)

        // Logs should be empty initially
        XCTAssertTrue(appState.logs(for: service.id).isEmpty)

        // Simulate log via public interface
        appState.serviceLogs[service.id] = [
            LogEntry(message: "hello", stream: .stdout)
        ]

        XCTAssertEqual(appState.logs(for: service.id).count, 1)
        XCTAssertEqual(appState.logs(for: service.id)[0].message, "hello")
    }

    func testClearLogs() {
        let appState = AppState()
        let serviceId = UUID()
        appState.serviceLogs[serviceId] = [
            LogEntry(message: "log1", stream: .stdout),
            LogEntry(message: "log2", stream: .stderr),
        ]

        appState.clearLogs(for: serviceId)

        XCTAssertTrue(appState.logs(for: serviceId).isEmpty)
    }

    func testLogsForUnknownServiceReturnsEmpty() {
        let appState = AppState()
        XCTAssertTrue(appState.logs(for: UUID()).isEmpty)
    }
}

// MARK: - Import/Export Tests

@MainActor
final class AppStateImportExportTests: XCTestCase {

    /// Helper to create a clean AppState with no pre-loaded environments
    private func cleanAppState() -> AppState {
        let appState = AppState()
        appState.environments = []
        appState.selectedEnvironmentId = nil
        return appState
    }

    func testExportImportRoundtrip() throws {
        let appState = cleanAppState()
        let env = appState.createEnvironment()
        let envId = env.id

        let service = Service(name: "web", ports: "80,443", command: "echo serve")
        appState.addService(to: envId, service: service)

        // Export
        guard let data = appState.exportEnvironment(envId) else {
            XCTFail("Export returned nil")
            return
        }

        // Import into fresh state
        let importState = cleanAppState()
        let result = importState.validateImport(data)

        switch result {
        case .success(let preview):
            XCTAssertEqual(preview.originalName, env.name)
            XCTAssertEqual(preview.services.count, 1)
            XCTAssertEqual(preview.services[0].name, "web")
            XCTAssertEqual(preview.services[0].ports, "80,443")
            XCTAssertFalse(preview.hasNameConflict)
            XCTAssertFalse(preview.hasIPConflicts)
        case .failure(let error):
            XCTFail("Import validation failed: \(error)")
        }
    }

    func testImportDetectsNameConflict() {
        let appState = cleanAppState()
        let env = appState.createEnvironment()

        guard let data = appState.exportEnvironment(env.id) else {
            XCTFail("Export returned nil")
            return
        }

        // Import into same state (same name exists)
        let result = appState.validateImport(data)

        switch result {
        case .success(let preview):
            XCTAssertTrue(preview.hasNameConflict)
            XCTAssertNotEqual(preview.suggestedName, preview.originalName)
        case .failure(let error):
            XCTFail("Import validation failed: \(error)")
        }
    }

    func testImportDetectsIPConflict() {
        let appState = cleanAppState()
        let env = appState.createEnvironment()

        guard let data = appState.exportEnvironment(env.id) else {
            XCTFail("Export returned nil")
            return
        }

        // Import into same state (same IPs exist)
        let result = appState.validateImport(data)

        switch result {
        case .success(let preview):
            XCTAssertTrue(preview.hasIPConflicts)
            // Suggested IPs should be different from original
            XCTAssertNotEqual(
                preview.suggestedInterfaces.map { $0.ip },
                preview.originalInterfaces.map { $0.ip }
            )
        case .failure(let error):
            XCTFail("Import validation failed: \(error)")
        }
    }

    func testImportRejectsNonLoopbackIP() {
        // Create JSON with a non-loopback IP
        let json = """
        {
            "version": "1.0",
            "exportedAt": "2024-01-01T00:00:00Z",
            "environment": {
                "name": "Bad Env",
                "interfaces": [{"ip": "192.168.1.1"}],
                "services": []
            }
        }
        """

        let appState = cleanAppState()
        let result = appState.validateImport(json.data(using: .utf8)!)

        switch result {
        case .success:
            XCTFail("Should have rejected non-loopback IP")
        case .failure(let error):
            // Should fail with invalid IP
            XCTAssertTrue(error.localizedDescription.contains("192.168.1.1"))
        }
    }

    func testImportRejects127001() {
        let json = """
        {
            "version": "1.0",
            "exportedAt": "2024-01-01T00:00:00Z",
            "environment": {
                "name": "Localhost Env",
                "interfaces": [{"ip": "127.0.0.1"}],
                "services": []
            }
        }
        """

        let appState = cleanAppState()
        let result = appState.validateImport(json.data(using: .utf8)!)

        switch result {
        case .success:
            XCTFail("Should have rejected 127.0.0.1")
        case .failure:
            break // Expected
        }
    }
}

// MARK: - ValidationService Extended Tests

final class ValidationServiceExtendedTests: XCTestCase {

    func testValidateIPRejects127001() {
        let validation = ValidationService.shared

        // 127.0.0.1 is the system default loopback — rejected as an alias target
        XCTAssertThrowsError(try validation.validateIP("127.0.0.1").get())
    }

    func testValidateIPBoundaryOctets() {
        let validation = ValidationService.shared

        // 127.0.0.0 should be valid
        XCTAssertNoThrow(try validation.validateIP("127.0.0.0").get())

        // 127.255.255.255 should be valid
        XCTAssertNoThrow(try validation.validateIP("127.255.255.255").get())

        // Octet > 255 should fail
        XCTAssertThrowsError(try validation.validateIP("127.0.0.256").get())
        XCTAssertThrowsError(try validation.validateIP("127.256.0.1").get())
    }

    func testValidateIPUniqueness() {
        let validation = ValidationService.shared

        let environments = [
            DevEnvironment(name: "Env1", interfaces: [Interface(ip: "127.0.0.2")]),
            DevEnvironment(name: "Env2", interfaces: [Interface(ip: "127.0.0.3")])
        ]

        // Should fail - IP already in use
        let result1 = validation.validateIPUniqueness("127.0.0.2", in: environments)
        XCTAssertThrowsError(try result1.get())

        // Should pass - IP not in use
        let result2 = validation.validateIPUniqueness("127.0.0.4", in: environments)
        XCTAssertNoThrow(try result2.get())

        // Should pass when excluding the environment that owns the IP
        let result3 = validation.validateIPUniqueness(
            "127.0.0.2",
            in: environments,
            excludingEnvironmentId: environments[0].id
        )
        XCTAssertNoThrow(try result3.get())
    }

    func testValidateEnvironmentNameUniqueness() {
        let validation = ValidationService.shared

        let environments = [
            DevEnvironment(name: "Production"),
            DevEnvironment(name: "Staging")
        ]

        // Case-insensitive duplicate
        let result1 = validation.validateEnvironmentName("production", in: environments)
        XCTAssertThrowsError(try result1.get())

        // Unique name
        let result2 = validation.validateEnvironmentName("Development", in: environments)
        XCTAssertNoThrow(try result2.get())

        // Empty name
        let result3 = validation.validateEnvironmentName("", in: environments)
        XCTAssertThrowsError(try result3.get())
    }

    func testValidateServiceAllFields() {
        let validation = ValidationService.shared

        // All valid
        let errors1 = validation.validateService(name: "web", ports: "80,443", command: "echo hi")
        XCTAssertTrue(errors1.isEmpty)

        // All invalid
        let errors2 = validation.validateService(name: "", ports: "", command: "")
        XCTAssertEqual(errors2.count, 3)

        // Partial invalid
        let errors3 = validation.validateService(name: "web", ports: "invalid", command: "echo hi")
        XCTAssertEqual(errors3.count, 1)
    }

    func testValidatePortEdgeCases() {
        let validation = ValidationService.shared

        // Port 1 (minimum valid)
        XCTAssertNoThrow(try validation.validatePorts("1").get())

        // Port 65535 (maximum valid)
        XCTAssertNoThrow(try validation.validatePorts("65535").get())

        // Port 65536 (out of range)
        XCTAssertThrowsError(try validation.validatePorts("65536").get())

        // Negative port
        XCTAssertThrowsError(try validation.validatePorts("-1").get())

        // Whitespace handling
        XCTAssertNoThrow(try validation.validatePorts(" 80 , 443 ").get())
    }
}

// MARK: - VariableResolver Extended Tests

final class VariableResolverExtendedTests: XCTestCase {

    func testNoVariablesInCommand() {
        let command = "echo hello world"
        let interfaces = [Interface(ip: "127.0.0.2")]

        let resolved = VariableResolver.resolve(command, interfaces: interfaces)
        XCTAssertEqual(resolved, "echo hello world")
    }

    func testUnresolvedVariablePreserved() {
        // $IP3 when only 2 interfaces exist
        let command = "cmd $IP $IP2 $IP3"
        let interfaces = [Interface(ip: "127.0.0.2"), Interface(ip: "127.0.0.3")]

        let resolved = VariableResolver.resolve(command, interfaces: interfaces)
        XCTAssertEqual(resolved, "cmd 127.0.0.2 127.0.0.3 $IP3")
    }

    func testEmptyInterfaceList() {
        let command = "cmd $IP"
        let interfaces: [Interface] = []

        let resolved = VariableResolver.resolve(command, interfaces: interfaces)
        XCTAssertEqual(resolved, "cmd $IP")
    }

    func testIPVariableInMiddleOfString() {
        let command = "--bind-address=$IP:8080"
        let interfaces = [Interface(ip: "127.0.0.2")]

        let resolved = VariableResolver.resolve(command, interfaces: interfaces)
        XCTAssertEqual(resolved, "--bind-address=127.0.0.2:8080")
    }
}

// MARK: - ConfigManager Tests

final class ConfigManagerTests: XCTestCase {

    private var tempDir: URL!
    private var manager: ConfigManager!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitTests-\(UUID().uuidString)", isDirectory: true)
        manager = ConfigManager(directory: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testSaveAndLoad() throws {
        let environments = [
            DevEnvironment(name: "Test", interfaces: [Interface(ip: "127.0.0.2")])
        ]

        try manager.save(environments: environments)
        let loaded = try manager.load()

        XCTAssertEqual(loaded.environments.count, 1)
        XCTAssertEqual(loaded.environments[0].name, "Test")
        XCTAssertEqual(loaded.environments[0].interfaces[0].ip, "127.0.0.2")
    }

    func testSaveCreatesBackup() throws {
        // Save initial config
        try manager.save(environments: [
            DevEnvironment(name: "First", interfaces: [Interface(ip: "127.0.0.2")])
        ])

        // Save again - should create backup of "First"
        try manager.save(environments: [
            DevEnvironment(name: "Second", interfaces: [Interface(ip: "127.0.0.3")])
        ])

        // Load current - should be "Second"
        let loaded = try manager.load()
        XCTAssertEqual(loaded.environments[0].name, "Second")

        // Backup should exist
        let backupURL = tempDir.appendingPathComponent("config.backup.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))
    }
}

// MARK: - KubernetesService Tests

final class KubernetesServiceTests: XCTestCase {

    func testParseContexts() {
        let output = "docker-desktop\nminikube\nprod-cluster\n"
        let contexts = KubernetesService.parseContexts(from: output)
        XCTAssertEqual(contexts, ["docker-desktop", "minikube", "prod-cluster"])
    }

    func testParseContextsFiltersEmpty() {
        let output = "\ndocker-desktop\n\n"
        let contexts = KubernetesService.parseContexts(from: output)
        XCTAssertEqual(contexts, ["docker-desktop"])
    }

    func testParseNamespaces() throws {
        let json = """
        {
            "items": [
                {"metadata": {"name": "default"}},
                {"metadata": {"name": "kube-system"}},
                {"metadata": {"name": "monitoring"}}
            ]
        }
        """.data(using: .utf8)!
        let namespaces = try KubernetesService.parseNamespaces(from: json)
        XCTAssertEqual(namespaces, ["default", "kube-system", "monitoring"])
    }

    func testParseServices() throws {
        let json = """
        {
            "items": [
                {
                    "metadata": {"name": "api-gateway", "namespace": "default"},
                    "spec": {
                        "type": "ClusterIP",
                        "ports": [
                            {"port": 8080, "protocol": "TCP"}
                        ]
                    }
                },
                {
                    "metadata": {"name": "elasticsearch", "namespace": "default"},
                    "spec": {
                        "type": "ClusterIP",
                        "ports": [
                            {"port": 9200, "protocol": "TCP", "name": "http"},
                            {"port": 9300, "protocol": "TCP", "name": "transport"}
                        ]
                    }
                }
            ]
        }
        """.data(using: .utf8)!
        let services = try KubernetesService.parseServices(from: json)
        XCTAssertEqual(services.count, 2)
        XCTAssertEqual(services[0].name, "api-gateway")
        XCTAssertEqual(services[0].ports.count, 1)
        XCTAssertEqual(services[0].ports[0].port, 8080)
        XCTAssertEqual(services[1].name, "elasticsearch")
        XCTAssertEqual(services[1].ports.count, 2)
    }

    func testParseServicesWithZeroPorts() throws {
        let json = """
        {
            "items": [
                {
                    "metadata": {"name": "external-svc", "namespace": "default"},
                    "spec": {
                        "type": "ExternalName"
                    }
                }
            ]
        }
        """.data(using: .utf8)!
        let services = try KubernetesService.parseServices(from: json)
        XCTAssertEqual(services.count, 1)
        XCTAssertFalse(services[0].hasPorts)
    }

    func testCommandGenerationSinglePort() {
        let svc = K8sService(
            name: "postgres",
            namespace: "default",
            type: "ClusterIP",
            ports: [K8sPort(port: 5432, name: nil, transportProtocol: "TCP")]
        )
        let cmd = KubernetesService.generateCommand(
            for: svc, tool: "kubectl", context: "prod-cluster"
        )
        XCTAssertEqual(cmd, "kubectl port-forward --address $IP svc/postgres 5432:5432 -n default --context prod-cluster")
    }

    func testCommandGenerationMultiPort() {
        let svc = K8sService(
            name: "elasticsearch",
            namespace: "monitoring",
            type: "ClusterIP",
            ports: [
                K8sPort(port: 9200, name: "http", transportProtocol: "TCP"),
                K8sPort(port: 9300, name: "transport", transportProtocol: "TCP")
            ]
        )
        let cmd = KubernetesService.generateCommand(
            for: svc, tool: "orb-kubectl", context: "dev"
        )
        XCTAssertEqual(cmd, "orb-kubectl port-forward --address $IP svc/elasticsearch 9200:9200 9300:9300 -n monitoring --context dev")
    }

    func testPortsString() {
        let svc = K8sService(
            name: "es",
            namespace: "default",
            type: "ClusterIP",
            ports: [
                K8sPort(port: 9200, name: nil, transportProtocol: "TCP"),
                K8sPort(port: 9300, name: nil, transportProtocol: "TCP")
            ]
        )
        XCTAssertEqual(KubernetesService.portsString(for: svc), "9200,9300")
    }

    func testDuplicateNameSuffix() {
        let existing = ["api-gateway", "postgres", "api-gateway-2"]
        XCTAssertEqual(KubernetesService.deduplicateName("redis", existing: existing), "redis")
        XCTAssertEqual(KubernetesService.deduplicateName("api-gateway", existing: existing), "api-gateway-3")
        XCTAssertEqual(KubernetesService.deduplicateName("postgres", existing: existing), "postgres-2")
    }

    func testServiceCreation() {
        let k8sSvc = K8sService(
            name: "api-gateway",
            namespace: "production",
            type: "ClusterIP",
            ports: [
                K8sPort(port: 8080, name: "http", transportProtocol: "TCP"),
                K8sPort(port: 8443, name: "https", transportProtocol: "TCP")
            ]
        )
        let name = KubernetesService.deduplicateName(k8sSvc.name, existing: [])
        let service = Service(
            name: name,
            ports: KubernetesService.portsString(for: k8sSvc),
            command: KubernetesService.generateCommand(for: k8sSvc, tool: "kubectl", context: "prod")
        )
        XCTAssertEqual(service.name, "api-gateway")
        XCTAssertEqual(service.ports, "8080,8443")
        XCTAssertEqual(service.command, "kubectl port-forward --address $IP svc/api-gateway 8080:8080 8443:8443 -n production --context prod")
        XCTAssertTrue(service.isEnabled)
    }

    func testParseMalformedJSON() {
        let badData = "not json".data(using: .utf8)!
        XCTAssertThrowsError(try KubernetesService.parseNamespaces(from: badData))
        XCTAssertThrowsError(try KubernetesService.parseServices(from: badData))
    }
}
