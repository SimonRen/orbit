import Foundation

/// Represents the current operational status of a service
enum ServiceStatus: String, Codable, Equatable {
    case stopped
    case starting
    case running
    case failed
    case stopping

    /// Whether the service is in a transitional state
    var isTransitioning: Bool {
        self == .starting || self == .stopping
    }

    /// Whether the service is currently active (running or transitioning)
    var isActive: Bool {
        self == .running || self == .starting || self == .stopping
    }
}
