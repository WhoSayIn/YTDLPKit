import XCTest

@testable import YTDLPKit

#if os(iOS)
  final class EmbeddedRuntimeSmokeTests: XCTestCase {
    func testBundledPythonRuntimeInitializesAndImportsYTDLP() async throws {
      let runtime = EmbeddedPythonRuntime()
      try await runtime.initialize(
        configuration: RuntimeConfiguration(
          module: .bundled,
          networkTimeout: .seconds(10),
          cookieFileURL: nil,
          enableAppleWebKitChallengeProvider: false,
          logger: { _ in }
        )
      )
    }
  }
#endif
