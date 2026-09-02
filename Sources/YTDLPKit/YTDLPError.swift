import Foundation

/// Failures produced while configuring or using YTDLPKit.
public enum YTDLPError: Error, Sendable, Equatable {
  case invalidRequest(reason: String)
  case runtimeUnavailable
  case initializationFailed(message: String)
  case incompatibleModule(reason: String)
  case extractionFailed(code: String?, message: String)
  case malformedOutput(reason: String)
  case decodingFailed(reason: String)
  case timedOut
  case cancelled
  case subprocessFailed(exitCode: Int32?, message: String)
}

/// A generic classification callers can use to apply their own retry policy.
public enum YTDLPFailureClassification: Sendable, Equatable {
  case rateLimited
  case forbidden
  case botVerificationRequired
  case timeout
  case transientNetwork
  case other
}

extension YTDLPError: LocalizedError, CustomStringConvertible {
  public var errorDescription: String? { description }

  public var description: String {
    switch self {
    case .invalidRequest(let reason):
      "Invalid request: \(SensitiveDataRedactor.redact(reason))"
    case .runtimeUnavailable:
      "The embedded Python runtime is unavailable."
    case .initializationFailed(let message):
      "Python runtime initialization failed: \(SensitiveDataRedactor.redact(message))"
    case .incompatibleModule(let reason):
      "The selected yt-dlp module is incompatible: \(SensitiveDataRedactor.redact(reason))"
    case .extractionFailed(let code, let message):
      "Extraction failed\(code.map { " (\(SensitiveDataRedactor.redact($0)))" } ?? ""): \(SensitiveDataRedactor.redact(message))"
    case .malformedOutput(let reason):
      "The runtime returned malformed output: \(SensitiveDataRedactor.redact(reason))"
    case .decodingFailed(let reason):
      "Could not decode yt-dlp metadata: \(SensitiveDataRedactor.redact(reason))"
    case .timedOut:
      "The extraction timed out."
    case .cancelled:
      "The extraction was cancelled."
    case .subprocessFailed(let exitCode, let message):
      "Runtime process failed\(exitCode.map { " (exit \($0))" } ?? ""): \(SensitiveDataRedactor.redact(message))"
    }
  }
}

extension YTDLPError {
  /// Classifies sanitized yt-dlp failures without prescribing retry behavior.
  public var failureClassification: YTDLPFailureClassification {
    if case .timedOut = self {
      return .timeout
    }

    let diagnostic: String
    switch self {
    case .extractionFailed(let code, let message):
      diagnostic = [code, message].compactMap { $0 }.joined(separator: " ")
    case .subprocessFailed(_, let message):
      diagnostic = message
    default:
      return .other
    }

    let normalized = diagnostic.lowercased()
    if Self.containsHTTPStatus(429, in: normalized)
      || normalized.contains("too many requests")
      || normalized.contains("rate limit")
    {
      return .rateLimited
    }
    if normalized.contains("sign in to confirm you're not a bot")
      || normalized.contains("sign in to confirm you’re not a bot")
      || normalized.contains("captcha")
      || normalized.contains("bot verification")
      || normalized.contains("verify you are human")
      || normalized.contains("verification challenge")
    {
      return .botVerificationRequired
    }
    if Self.containsHTTPStatus(403, in: normalized) || normalized.contains("forbidden") {
      return .forbidden
    }
    if normalized.contains("timed out") || normalized.contains("timeout") {
      return .timeout
    }
    if [500, 502, 503, 504].contains(where: { Self.containsHTTPStatus($0, in: normalized) })
      || normalized.contains("temporary failure in name resolution")
      || normalized.contains("temporarily unavailable")
      || normalized.contains("network is unreachable")
      || normalized.contains("connection reset")
      || normalized.contains("connection aborted")
      || normalized.contains("connection refused")
      || normalized.contains("remote end closed connection")
      || normalized.contains("name or service not known")
      || normalized.contains("dns lookup failed")
    {
      return .transientNetwork
    }
    return .other
  }

  private static func containsHTTPStatus(_ status: Int, in diagnostic: String) -> Bool {
    diagnostic.contains("http error \(status)")
      || diagnostic.contains("http \(status)")
      || diagnostic.contains("status code \(status)")
      || diagnostic.contains("status: \(status)")
  }

  var sanitized: Self {
    switch self {
    case .invalidRequest(let reason):
      return .sanitizedInvalidRequest(reason)
    case .runtimeUnavailable, .timedOut, .cancelled:
      return self
    case .initializationFailed(let message):
      return .sanitizedInitializationFailure(message)
    case .incompatibleModule(let reason):
      return .sanitizedIncompatibleModule(reason)
    case .extractionFailed(let code, let message):
      return .sanitizedExtractionFailure(code: code, message: message)
    case .malformedOutput(let reason):
      return .sanitizedMalformedOutput(reason)
    case .decodingFailed(let reason):
      return .sanitizedDecodingFailure(reason)
    case .subprocessFailed(let exitCode, let message):
      return .sanitizedSubprocessFailure(exitCode: exitCode, message: message)
    }
  }

  static func sanitizedInvalidRequest(_ reason: String) -> Self {
    .invalidRequest(reason: SensitiveDataRedactor.redact(reason))
  }

  static func sanitizedInitializationFailure(_ message: String) -> Self {
    .initializationFailed(message: SensitiveDataRedactor.redact(message))
  }

  static func sanitizedIncompatibleModule(_ reason: String) -> Self {
    .incompatibleModule(reason: SensitiveDataRedactor.redact(reason))
  }

  static func sanitizedExtractionFailure(code: String?, message: String) -> Self {
    .extractionFailed(
      code: code.map(SensitiveDataRedactor.redact),
      message: SensitiveDataRedactor.redact(message)
    )
  }

  static func sanitizedMalformedOutput(_ reason: String) -> Self {
    .malformedOutput(reason: SensitiveDataRedactor.redact(reason))
  }

  static func sanitizedDecodingFailure(_ reason: String) -> Self {
    .decodingFailed(reason: SensitiveDataRedactor.redact(reason))
  }

  static func sanitizedSubprocessFailure(exitCode: Int32?, message: String) -> Self {
    .subprocessFailed(
      exitCode: exitCode,
      message: SensitiveDataRedactor.redact(message)
    )
  }
}
