import Foundation

/// Configuration applied before the embedded Python runtime is initialized.
public struct YTDLPConfiguration: Sendable {
  /// Selects the yt-dlp Python module loaded by the runtime.
  public enum Module: Sendable, Equatable {
    /// The compatible yt-dlp module shipped with YTDLPKit.
    case bundled

    /// A local module whose contents must match `expectedSHA256`.
    ///
    /// The file is validated before it is imported. YTDLPKit never downloads
    /// executable code at runtime.
    case local(url: URL, expectedSHA256: String)
  }

  public var module: Module
  public var networkTimeout: Duration
  /// Enables the bundled experimental Apple WebKit JavaScript challenge provider.
  ///
  /// The provider is excluded from Python's import path by default. Set this
  /// before the first extraction only when the application accepts the
  /// provider's additional compatibility and review surface.
  public var enableAppleWebKitChallengeProvider: Bool
  public var logHandler: (@Sendable (YTDLPLogEvent) -> Void)?

  public init(
    module: Module = .bundled,
    networkTimeout: Duration = .seconds(30),
    enableAppleWebKitChallengeProvider: Bool = false,
    logHandler: (@Sendable (YTDLPLogEvent) -> Void)? = nil
  ) {
    self.module = module
    self.networkTimeout = networkTimeout
    self.enableAppleWebKitChallengeProvider = enableAppleWebKitChallengeProvider
    self.logHandler = logHandler
  }
}
