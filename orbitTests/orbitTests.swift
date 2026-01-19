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
}
