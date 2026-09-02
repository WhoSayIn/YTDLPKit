import Foundation

/// A concurrency-safe client for metadata extraction through yt-dlp.
///
/// The actor owns runtime initialization and serializes every Python call.
public actor YTDLPClient {
  private enum InitializationState {
    case pending
    case ready
    case failed(YTDLPError)
  }

  private let configuration: YTDLPConfiguration
  private let runtime: any YTDLPRuntime
  private let gate = AsyncSerialGate()
  private var initializationState: InitializationState = .pending

  public init(configuration: YTDLPConfiguration = .init()) throws {
    try Self.validate(configuration)
    self.configuration = configuration
    runtime = YTDLPRuntimeFactory.makeDefault()
  }

  init(configuration: YTDLPConfiguration = .init(), runtime: any YTDLPRuntime) throws {
    try Self.validate(configuration)
    self.configuration = configuration
    self.runtime = runtime
  }

  public func extract(_ request: ExtractionRequest) async throws -> MediaInfo {
    guard let scheme = request.url.scheme?.lowercased(), scheme == "http" || scheme == "https"
    else {
      throw YTDLPError.sanitizedInvalidRequest("Only HTTP and HTTPS URLs are supported.")
    }
    return try await serialized {
      try await self.initializeIfNeeded()
      await self.emit(.debug, "Starting metadata extraction")
      let response = try await self.execute(
        .extract(url: request.url, includePlaylists: request.includePlaylists)
      )
      let info = try RuntimeResponseDecoder.decodeMediaInfo(from: response)
      await self.emit(.info, "Metadata extraction completed for media id \(info.id)")
      return info
    }
  }

  public func search(_ query: String, limit: Int = 20) async throws -> [MediaInfo] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw YTDLPError.sanitizedInvalidRequest("The search query is empty.")
    }
    guard (1...100).contains(limit) else {
      throw YTDLPError.sanitizedInvalidRequest("Search limit must be between 1 and 100.")
    }
    return try await serialized {
      try await self.initializeIfNeeded()
      await self.emit(.debug, "Starting metadata search")
      let response = try await self.execute(.search(query: trimmed, limit: limit))
      let results = try RuntimeResponseDecoder.decodeSearchResults(from: response)
      await self.emit(.info, "Metadata search completed with \(results.count) results")
      return results
    }
  }

  private func serialized<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws
    -> T
  {
    let token = UUID()
    do {
      try await withTaskCancellationHandler {
        try await gate.acquire(token: token)
      } onCancel: {
        Task { await self.gate.cancel(token: token) }
      }
    } catch is CancellationError {
      throw YTDLPError.cancelled
    }

    do {
      defer { Task { await gate.release() } }
      try Task.checkCancellation()
      return try await operation()
    } catch is CancellationError {
      throw YTDLPError.cancelled
    } catch let error as YTDLPError {
      throw error.sanitized
    } catch {
      throw YTDLPError.sanitizedExtractionFailure(
        code: nil,
        message: String(describing: error)
      )
    }
  }

  private func initializeIfNeeded() async throws {
    switch initializationState {
    case .ready:
      return
    case .failed(let error):
      throw error
    case .pending:
      do {
        try await runtime.initialize(
          configuration: RuntimeConfiguration(
            module: configuration.module,
            networkTimeout: configuration.networkTimeout,
            cookieFileURL: configuration.cookieFileURL,
            enableAppleWebKitChallengeProvider: configuration.enableAppleWebKitChallengeProvider,
            logger: { [handler = configuration.logHandler] event in handler?(event) }
          )
        )
        initializationState = .ready
      } catch is CancellationError {
        // A cancelled first request must not permanently poison the client.
        initializationState = .pending
        throw YTDLPError.cancelled
      } catch let error as YTDLPError {
        let sanitized = error.sanitized
        initializationState = .failed(sanitized)
        throw sanitized
      } catch {
        let mapped = YTDLPError.sanitizedInitializationFailure(String(describing: error))
        initializationState = .failed(mapped)
        throw mapped
      }
    }
  }

  private func execute(_ invocation: RuntimeInvocation) async throws -> RuntimeResponse {
    try Task.checkCancellation()
    do {
      let response = try await runtime.execute(invocation)
      try Task.checkCancellation()
      return response
    } catch is CancellationError {
      throw YTDLPError.cancelled
    }
  }

  private func emit(_ level: YTDLPLogEvent.Level, _ message: String) {
    configuration.logHandler?(YTDLPLogEvent(level: level, message: message))
  }

  private static func validate(_ configuration: YTDLPConfiguration) throws {
    guard configuration.networkTimeout > .zero else {
      throw YTDLPError.sanitizedInvalidRequest("Network timeout must be greater than zero.")
    }
    if let cookieFileURL = configuration.cookieFileURL {
      guard cookieFileURL.isFileURL, !cookieFileURL.path.isEmpty else {
        throw YTDLPError.sanitizedInvalidRequest("The cookie file must use a local file URL.")
      }
    }
    if case .local(let url, let digest) = configuration.module {
      guard url.isFileURL else {
        throw YTDLPError.sanitizedInvalidRequest("A local yt-dlp module must use a file URL.")
      }
      let hexadecimal = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
      guard digest.count == 64, digest.unicodeScalars.allSatisfy(hexadecimal.contains) else {
        throw YTDLPError.sanitizedInvalidRequest(
          "The expected SHA-256 must contain 64 hexadecimal characters."
        )
      }
    }
  }

  func pendingRequestCount() async -> Int {
    await gate.waitingCount
  }
}
