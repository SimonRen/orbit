import Foundation

/// Represents the current operational status of a service
enum ServiceStatus: String, Codable, Equatable {
    case stopped
    case starting
    case running
    case failed
    case stopping
    case reconnecting

    /// Whether the service is in a transitional state (user cannot interact)
    /// Note: `.reconnecting` is intentionally excluded — users must be able to stop a reconnecting service
    var isTransitioning: Bool {
        self == .starting || self == .stopping
    }

    /// Whether the service is currently active (running or transitioning)
    var isActive: Bool {
        self == .running || self == .starting || self == .stopping || self == .reconnecting
    }
}
