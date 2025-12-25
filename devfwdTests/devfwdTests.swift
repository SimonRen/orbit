import XCTest
@testable import devfwd

final class DEV_FwdTests: XCTestCase {

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
        let interfaces = ["127.0.0.2"]

        let resolved = VariableResolver.resolve(command, interfaces: interfaces)

        XCTAssertEqual(resolved, "kubectl port-forward svc/auth 127.0.0.2:8080:8080")
    }

    func testMultipleVariableResolution() {
        let command = "ssh -L $IP:3000:localhost:3000 -L $IP2:3001:localhost:3001"
        let interfaces = ["127.0.0.2", "127.0.0.3"]

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
            interfaces: ["127.0.0.2"],
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
}
