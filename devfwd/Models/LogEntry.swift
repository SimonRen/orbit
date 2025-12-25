import Foundation

/// Represents which output stream a log entry came from
enum LogStream: String, Codable {
    case stdout
    case stderr
}

/// A single log entry captured from a service process
struct LogEntry: Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let message: String
    let stream: LogStream

    init(id: UUID = UUID(), timestamp: Date = Date(), message: String, stream: LogStream) {
        self.id = id
        self.timestamp = timestamp
        self.message = message
        self.stream = stream
    }

    /// Formatted timestamp string for display
    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return "[\(formatter.string(from: timestamp))]"
    }
}
