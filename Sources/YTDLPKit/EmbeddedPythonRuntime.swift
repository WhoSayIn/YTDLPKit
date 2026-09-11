#if os(iOS)
  import CryptoKit
  import CYTDLPPythonBridge
  import Foundation

  /// The private, process-wide CPython implementation. No Python value crosses
  /// this boundary; the bridge returns sanitized UTF-8 JSON owned by Swift.
  final class EmbeddedPythonRuntime: YTDLPRuntime, @unchecked Sendable {
    private let state = NSLock()
    private var configuration: RuntimeConfiguration?

    func initialize(configuration: RuntimeConfiguration) async throws {
      try await EmbeddedPythonCoordinator.shared.initialize(configuration: configuration)
      state.withLock { self.configuration = configuration }
    }

    func execute(_ invocation: RuntimeInvocation) async throws -> RuntimeResponse {
      guard let configuration = state.withLock({ configuration }) else {
        throw YTDLPError.initializationFailed(
          message: "The runtime was used before initialization.")
      }
      return try await EmbeddedPythonCoordinator.shared.execute(
        invocation,
        configuration: configuration
      )
    }

    #if DEBUG
      static var resourceValidationCount: Int { PythonResourceLayout.validationCount }
    #endif
  }

  private actor EmbeddedPythonCoordinator {
    static let shared = EmbeddedPythonCoordinator()

    private enum State {
      case pending
      case initializing(resources: PythonResourceLayout, task: Task<Void, any Error>)
      case ready(resources: PythonResourceLayout)
      case failed(YTDLPError)
    }

    private let executor = DispatchQueue(label: "org.ytdlpkit.python", qos: .userInitiated)
    private var state: State = .pending

    func initialize(configuration: RuntimeConfiguration) async throws {
      switch state {
      case .initializing(let resources, let task):
        try resources.requireMatchingIdentity(
          module: configuration.module,
          enableAppleWebKitChallengeProvider: configuration.enableAppleWebKitChallengeProvider,
          conflictReason:
            "CPython initialization has already started with a different yt-dlp module."
        )
        try await task.value
        return
      case .ready(let resources):
        try resources.requireMatchingIdentity(
          module: configuration.module,
          enableAppleWebKitChallengeProvider: configuration.enableAppleWebKitChallengeProvider,
          conflictReason: "CPython is already initialized with a different yt-dlp module."
        )
        return
      case .failed(let error):
        throw error
      case .pending:
        break
      }

      let resources: PythonResourceLayout
      do {
        resources = try PythonResourceLayout.resolve(
          module: configuration.module,
          enableAppleWebKitChallengeProvider: configuration.enableAppleWebKitChallengeProvider
        )
      } catch let error as YTDLPError {
        throw error
      } catch {
        throw YTDLPError.incompatibleModule(
          reason: SensitiveDataRedactor.redact(String(describing: error))
        )
      }

      let initialization = Task {
        try await runOnExecutor {
          var message: UnsafeMutablePointer<CChar>?
          let succeeded = ytdlpkit_python_initialize(
            resources.pythonHome.path,
            resources.standardLibrary.path,
            resources.platformLibrary.path,
            resources.dynamicModules.path,
            resources.certifiModule.path,
            resources.ytDLPModule.path,
            resources.pluginModule?.path,
            &message
          )
          defer { ytdlpkit_python_string_free(message) }
          guard succeeded else {
            let detail =
              message.map { String(cString: $0) }
              ?? "The CPython C API rejected its configuration."
            throw YTDLPError.initializationFailed(
              message: SensitiveDataRedactor.redact(detail)
            )
          }
        }
      }
      state = .initializing(resources: resources, task: initialization)

      do {
        try await initialization.value
        state = .ready(resources: resources)
      } catch let error as YTDLPError {
        state = .failed(error)
        throw error
      } catch {
        let mapped = YTDLPError.initializationFailed(message: String(describing: error))
        state = .failed(mapped)
        throw mapped
      }
    }

    func execute(
      _ invocation: RuntimeInvocation,
      configuration: RuntimeConfiguration
    ) async throws -> RuntimeResponse {
      guard case .ready = state else {
        throw YTDLPError.initializationFailed(message: "CPython is not ready.")
      }

      let payload = try PythonInvocationPayload(
        invocation,
        timeout: configuration.networkTimeout,
        cookieFileURL: configuration.cookieFileURL
      )
      .encoded()
      let job = PythonExecutionJob(logger: configuration.logger)

      return try await withTaskCancellationHandler {
        try await runOnExecutor {
          if job.isCancelled { throw YTDLPError.cancelled }
          let context = Unmanaged.passUnretained(job).toOpaque()
          let result = payload.withUnsafeBytes { bytes in
            ytdlpkit_python_execute(
              bytes.bindMemory(to: UInt8.self).baseAddress,
              bytes.count,
              pythonRuntimeLogCallback,
              pythonRuntimeCancelCallback,
              context
            )
          }
          defer { ytdlpkit_python_result_free(result) }

          if result.cancelled || job.isCancelled { throw YTDLPError.cancelled }
          if let error = result.error {
            let message = String(cString: error)
            if message.localizedCaseInsensitiveContains("timed out")
              || message.localizedCaseInsensitiveContains("timeout")
            {
              throw YTDLPError.timedOut
            }
            throw YTDLPError.extractionFailed(
              code: PythonErrorCode.parse(message),
              message: SensitiveDataRedactor.redact(message)
            )
          }
          guard let bytes = result.bytes, result.length > 0 else {
            throw YTDLPError.malformedOutput(reason: "The Python bridge produced no JSON bytes.")
          }
          return RuntimeResponse(sanitizedJSON: Data(bytes: bytes, count: result.length))
        }
      } onCancel: {
        job.cancel()
      }
    }

    private func runOnExecutor<T: Sendable>(
      _ operation: @escaping @Sendable () throws -> T
    ) async throws -> T {
      try await withCheckedThrowingContinuation { continuation in
        executor.async {
          do {
            continuation.resume(returning: try operation())
          } catch {
            continuation.resume(throwing: error)
          }
        }
      }
    }
  }

  private final class PythonExecutionJob: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    let logger: @Sendable (YTDLPLogEvent) -> Void

    init(logger: @escaping @Sendable (YTDLPLogEvent) -> Void) {
      self.logger = logger
    }

    var isCancelled: Bool { lock.withLock { cancelled } }
    func cancel() { lock.withLock { cancelled = true } }
  }

  private let pythonRuntimeLogCallback:
    @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Void =
      { context, level, message in
        guard let context, let message else { return }
        let job = Unmanaged<PythonExecutionJob>.fromOpaque(context).takeUnretainedValue()
        let level = level.map { String(cString: $0) } ?? "info"
        let eventLevel = YTDLPLogEvent.Level(rawValue: level) ?? .info
        job.logger(YTDLPLogEvent(level: eventLevel, message: String(cString: message)))
      }

  private let pythonRuntimeCancelCallback: @convention(c) (UnsafeMutableRawPointer?) -> Bool = {
    context in
    guard let context else { return true }
    return Unmanaged<PythonExecutionJob>.fromOpaque(context).takeUnretainedValue().isCancelled
  }

  private struct PythonInvocationPayload: Encodable, Sendable {
    let kind: String
    let url: String?
    let includePlaylists: Bool?
    let query: String?
    let limit: Int?
    let timeout: Double
    let cookieFilePath: String?

    init(
      _ invocation: RuntimeInvocation,
      timeout: Duration,
      cookieFileURL: URL?
    ) throws {
      let components = timeout.components
      self.timeout = Double(components.seconds) + Double(components.attoseconds) / 1e18
      cookieFilePath = cookieFileURL?.standardizedFileURL.path
      guard self.timeout.isFinite, self.timeout > 0 else {
        throw YTDLPError.invalidRequest(reason: "Network timeout is outside the supported range.")
      }
      switch invocation {
      case .extract(let url, let includePlaylists):
        kind = "extract"
        self.url = url.absoluteString
        self.includePlaylists = includePlaylists
        query = nil
        limit = nil
      case .search(let query, let limit):
        kind = "search"
        url = nil
        includePlaylists = nil
        self.query = query
        self.limit = limit
      }
    }

    func encoded() throws -> Data {
      do { return try JSONEncoder().encode(self) } catch {
        throw YTDLPError.invalidRequest(reason: "Could not encode the runtime request.")
      }
    }
  }

  private struct PythonResourceLayout: Sendable {
    private static let certifiDigest =
      "62f22742b58a1a33014a2b6b706588a8d7e2a88ae7bd1a6ebe8c992928483775"
    private static let pluginDigest =
      "930ce1c170fa01ee7316e5c8cf82190c1a68961ab3d8592d97b9c3bb919b7173"
    private static let bundledModuleDigest =
      "1fa6733c37ea6fb51c99ad8fe785e7b7e5f3246c9b980230329d4fb72ed8d4d6"
    #if DEBUG
      private static let validationCounter = FileValidationCounter()
      static var validationCount: Int { validationCounter.value }
    #endif

    let pythonHome: URL
    let standardLibrary: URL
    let platformLibrary: URL
    let dynamicModules: URL
    let certifiModule: URL
    let ytDLPModule: URL
    let pluginModule: URL?
    let moduleIdentity: String

    static func resolve(
      module: YTDLPConfiguration.Module,
      enableAppleWebKitChallengeProvider: Bool
    ) throws -> Self {
      let standardLibrary = try requiredResource(
        names: [
          ("python313", "zip", "PythonRuntime/python/lib"),
          ("python313", "zip", "python/lib"),
        ],
        description: "the CPython 3.13 standard library"
      )
      let platformLibrary = standardLibrary.deletingLastPathComponent()
        .appendingPathComponent("python3.13", isDirectory: true)
      var platformLibraryIsDirectory: ObjCBool = false
      guard
        FileManager.default.fileExists(
          atPath: platformLibrary.path,
          isDirectory: &platformLibraryIsDirectory
        ), platformLibraryIsDirectory.boolValue
      else {
        throw YTDLPError.initializationFailed(
          message: "Could not locate the CPython 3.13 platform library in package resources."
        )
      }
      let dynamicModules = platformLibrary.appendingPathComponent("lib-dynload", isDirectory: true)
      guard FileManager.default.fileExists(atPath: dynamicModules.path) else {
        throw YTDLPError.runtimeUnavailable
      }
      let pythonHome = standardLibrary.deletingLastPathComponent().deletingLastPathComponent()

      let certifiModule = try requiredResource(
        names: [("certifi-2026.7.22-py3-none-any", "whl", "Python")],
        description: "the certifi CA bundle"
      )
      try validateFile(certifiModule, expectedSHA256: certifiDigest)

      let plugin: URL?
      if enableAppleWebKitChallengeProvider {
        let selectedPlugin = try requiredResource(
          names: [("yt-dlp-apple-webkit-jsi-0.1.1-noextapp-53dcc9d", "zip", "Python")],
          description: "the Apple WebKit JavaScript challenge provider"
        )
        try validateFile(selectedPlugin, expectedSHA256: pluginDigest)
        plugin = selectedPlugin
      } else {
        plugin = nil
      }

      let selected: URL
      switch module {
      case .bundled:
        selected = try requiredResource(
          names: [("yt-dlp-2026.08.19", "pyz", "Python")],
          description: "the bundled yt-dlp module"
        )
        try validateFile(selected, expectedSHA256: bundledModuleDigest)
      case .local(let url, let expectedSHA256):
        selected = try validateLocalModuleURL(url)
        try validateFile(selected, expectedSHA256: expectedSHA256)
      }

      return Self(
        pythonHome: pythonHome,
        standardLibrary: standardLibrary,
        platformLibrary: platformLibrary,
        dynamicModules: dynamicModules,
        certifiModule: certifiModule,
        ytDLPModule: selected,
        pluginModule: plugin,
        moduleIdentity: identity(
          module: module,
          enableAppleWebKitChallengeProvider: enableAppleWebKitChallengeProvider
        )
      )
    }

    func requireMatchingIdentity(
      module: YTDLPConfiguration.Module,
      enableAppleWebKitChallengeProvider: Bool,
      conflictReason: String
    ) throws {
      guard
        moduleIdentity
          == Self.identity(
            module: module,
            enableAppleWebKitChallengeProvider: enableAppleWebKitChallengeProvider
          )
      else {
        throw YTDLPError.incompatibleModule(reason: conflictReason)
      }
    }

    private static func identity(
      module: YTDLPConfiguration.Module,
      enableAppleWebKitChallengeProvider: Bool
    ) -> String {
      let moduleIdentity: String
      switch module {
      case .bundled:
        moduleIdentity = "bundled:\(bundledModuleDigest)"
      case .local(let url, let expectedSHA256):
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        moduleIdentity = "local:\(path):\(expectedSHA256.lowercased())"
      }
      let providerIdentity =
        enableAppleWebKitChallengeProvider
        ? "apple-webkit-jsi:\(pluginDigest)"
        : "none"
      return "\(moduleIdentity):certifi:\(certifiDigest):challenge-provider:\(providerIdentity)"
    }

    private static func requiredResource(
      names: [(String, String, String)],
      description: String
    ) throws -> URL {
      for (name, extensionName, subdirectory) in names {
        if let resourceRoot = Bundle.module.resourceURL {
          let candidate =
            resourceRoot
            .appendingPathComponent(subdirectory, isDirectory: true)
            .appendingPathComponent(name)
            .appendingPathExtension(extensionName)
          if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        if let url = Bundle.module.url(
          forResource: name,
          withExtension: extensionName,
          subdirectory: subdirectory
        ) {
          return url
        }
      }
      throw YTDLPError.initializationFailed(
        message: "Could not locate \(description) in package resources.")
    }

    private static func validateLocalModuleURL(_ url: URL) throws -> URL {
      let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
      let values = try resolved.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
      guard values.isRegularFile == true, values.isSymbolicLink != true else {
        throw YTDLPError.incompatibleModule(
          reason: "The local module must be a regular, non-symbolic-link file.")
      }
      guard ["pyz", "zip", "py"].contains(resolved.pathExtension.lowercased()) else {
        throw YTDLPError.incompatibleModule(
          reason: "The local module must be a .pyz, .zip, or .py file.")
      }

      let allowedRoots = [
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
        FileManager.default.temporaryDirectory,
        Bundle.main.bundleURL,
      ].map { $0.standardizedFileURL.resolvingSymlinksInPath().path + "/" }
      guard allowedRoots.contains(where: { resolved.path.hasPrefix($0) }) else {
        throw YTDLPError.incompatibleModule(
          reason: "The local module is outside the application container.")
      }
      return resolved
    }

    private static func validateFile(_ url: URL, expectedSHA256: String) throws {
      #if DEBUG
        validationCounter.increment()
      #endif
      let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
      guard let size = attributes[.size] as? NSNumber, size.int64Value > 0,
        size.int64Value <= 128 * 1_024 * 1_024
      else {
        throw YTDLPError.incompatibleModule(reason: "The Python module has an invalid file size.")
      }

      let handle = try FileHandle(forReadingFrom: url)
      defer { try? handle.close() }
      var hasher = SHA256()
      while true {
        let data = try handle.read(upToCount: 1_048_576) ?? Data()
        if data.isEmpty { break }
        hasher.update(data: data)
      }
      let actual = hasher.finalize().map { String(format: "%02x", $0) }.joined()
      guard actual == expectedSHA256.lowercased() else {
        throw YTDLPError.incompatibleModule(
          reason: "The Python module SHA-256 does not match its pinned digest.")
      }
    }
  }

  #if DEBUG
    private final class FileValidationCounter: @unchecked Sendable {
      private let lock = NSLock()
      private var count = 0

      var value: Int { lock.withLock { count } }
      func increment() { lock.withLock { count += 1 } }
    }
  #endif

  private enum PythonErrorCode {
    static func parse(_ message: String) -> String? {
      guard let separator = message.firstIndex(of: ":") else { return nil }
      let code = String(message[..<separator])
      return code.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" } ? code : nil
    }
  }
#endif
