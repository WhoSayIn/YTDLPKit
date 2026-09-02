import Foundation

protocol YTDLPRuntime: Sendable {
  func initialize(configuration: RuntimeConfiguration) async throws
  func execute(_ invocation: RuntimeInvocation) async throws -> RuntimeResponse
}

struct RuntimeConfiguration: Sendable {
  let module: YTDLPConfiguration.Module
  let networkTimeout: Duration
  let cookieFileURL: URL?
  let enableAppleWebKitChallengeProvider: Bool
  let logger: @Sendable (YTDLPLogEvent) -> Void
}

enum RuntimeInvocation: Sendable, Equatable {
  case extract(url: URL, includePlaylists: Bool)
  case search(query: String, limit: Int)
}

struct RuntimeResponse: Sendable, Equatable {
  var sanitizedJSON: Data?
  var diagnostic: String?
  var exitCode: Int32?

  init(sanitizedJSON: Data?, diagnostic: String? = nil, exitCode: Int32? = nil) {
    self.sanitizedJSON = sanitizedJSON
    self.diagnostic = diagnostic
    self.exitCode = exitCode
  }
}

struct UnavailableYTDLPRuntime: YTDLPRuntime {
  func initialize(configuration: RuntimeConfiguration) async throws {
    throw YTDLPError.runtimeUnavailable
  }

  func execute(_ invocation: RuntimeInvocation) async throws -> RuntimeResponse {
    throw YTDLPError.runtimeUnavailable
  }
}

enum YTDLPRuntimeFactory {
  static func makeDefault() -> any YTDLPRuntime {
    #if os(iOS)
      EmbeddedPythonRuntime()
    #else
      UnavailableYTDLPRuntime()
    #endif
  }
}

enum RuntimeResponseDecoder {
  static func decodeMediaInfo(from response: RuntimeResponse) throws -> MediaInfo {
    let data = try requireOutput(from: response)
    do {
      return try JSONDecoder().decode(MediaInfo.self, from: data)
    } catch let error as YTDLPError {
      throw error
    } catch {
      throw YTDLPError.sanitizedDecodingFailure(String(describing: error))
    }
  }

  static func decodeSearchResults(from response: RuntimeResponse) throws -> [MediaInfo] {
    let data = try requireOutput(from: response)
    do {
      if let direct = try? JSONDecoder().decode([LossyMediaInfo].self, from: data) {
        return direct.compactMap(\.value)
      }
      return try JSONDecoder().decode(MediaInfo.self, from: data).entries
    } catch {
      throw YTDLPError.sanitizedDecodingFailure(String(describing: error))
    }
  }

  private static func requireOutput(from response: RuntimeResponse) throws -> Data {
    guard let data = response.sanitizedJSON, !data.isEmpty else {
      if response.exitCode != nil || response.diagnostic != nil {
        throw YTDLPError.sanitizedSubprocessFailure(
          exitCode: response.exitCode,
          message: response.diagnostic ?? "No metadata output was produced."
        )
      }
      throw YTDLPError.sanitizedMalformedOutput("No metadata output was produced.")
    }
    return data
  }
}
