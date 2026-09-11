import XCTest

@testable import YTDLPKit

#if os(iOS)
  final class EmbeddedRuntimeSmokeTests: XCTestCase {
    func testBundledPythonRuntimeInitializesAndImportsYTDLP() async throws {
      let configuration = RuntimeConfiguration(
        module: .bundled,
        networkTimeout: .seconds(10),
        cookieFileURL: nil,
        enableAppleWebKitChallengeProvider: false,
        logger: { _ in }
      )
      let firstRuntime = EmbeddedPythonRuntime()
      try await firstRuntime.initialize(configuration: configuration)
      let validationCountAfterFirstInitialization = EmbeddedPythonRuntime.resourceValidationCount

      let secondRuntime = EmbeddedPythonRuntime()
      try await secondRuntime.initialize(configuration: configuration)

      XCTAssertGreaterThan(validationCountAfterFirstInitialization, 0)
      XCTAssertEqual(
        EmbeddedPythonRuntime.resourceValidationCount,
        validationCountAfterFirstInitialization,
        "A second client must reuse the process-wide validated embedded-resource layout."
      )

      let mismatchedRuntime = EmbeddedPythonRuntime()
      do {
        try await mismatchedRuntime.initialize(
          configuration: RuntimeConfiguration(
            module: .bundled,
            networkTimeout: .seconds(10),
            cookieFileURL: nil,
            enableAppleWebKitChallengeProvider: true,
            logger: { _ in }
          )
        )
        XCTFail("Expected a process-wide module identity mismatch.")
      } catch let error as YTDLPError {
        guard case .incompatibleModule = error else {
          return XCTFail("Expected incompatibleModule, got \(error)")
        }
      }
      XCTAssertEqual(
        EmbeddedPythonRuntime.resourceValidationCount,
        validationCountAfterFirstInitialization,
        "Identity mismatch rejection must not rehash embedded resources."
      )
    }
  }
#endif
