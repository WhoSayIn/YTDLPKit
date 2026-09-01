import Foundation

/// A sanitized diagnostic event emitted by YTDLPKit.
public struct YTDLPLogEvent: Sendable, Equatable {
  public enum Level: String, Sendable, Equatable {
    case debug
    case info
    case warning
    case error
  }

  public let level: Level
  public let message: String

  public init(level: Level, message: String) {
    self.level = level
    self.message = SensitiveDataRedactor.redact(message)
  }
}
