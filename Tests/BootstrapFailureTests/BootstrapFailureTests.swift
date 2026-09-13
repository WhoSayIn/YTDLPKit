import XCTest

@testable import YTDLPKit

#if os(iOS)
  import CryptoKit
  import CYTDLPPythonBridge
  import PythonBootstrapProbe

  final class BootstrapFailureTests: XCTestCase {
    // Keep this in its own test target/process, separate from the success smoke test.
    func testBootstrapFailureIsTerminalAndReleasesTheInitializingThread() async throws {
      let fixture = try XCTUnwrap(
        Bundle.module.url(
          forResource: "incompatible-ytdlp", withExtension: "zip", subdirectory: "Fixtures")
      )
      let moduleURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(UUID().uuidString).zip")
      try FileManager.default.copyItem(at: fixture, to: moduleURL)
      defer { try? FileManager.default.removeItem(at: moduleURL) }
      let digest = SHA256.hash(data: try Data(contentsOf: moduleURL))
        .map { String(format: "%02x", $0) }.joined()
      let module = YTDLPConfiguration.Module.local(url: moduleURL, expectedSHA256: digest)
      let resources = try PythonResourceLayout.resolve(
        module: module, enableAppleWebKitChallengeProvider: false
      )

      // All checks in this closure run synchronously on the initializing OS thread.
      let failure = await Task.detached { () -> String? in
        guard !ytdlpkit_test_python_initialized() else {
          XCTFail("The bootstrap failure regression requires a fresh process.")
          return nil
        }
        var message: UnsafeMutablePointer<CChar>?
        let succeeded = ytdlpkit_python_initialize(
          resources.pythonHome.path,
          resources.standardLibrary.path,
          resources.platformLibrary.path,
          resources.dynamicModules.path,
          resources.certifiModule.path,
          resources.ytDLPModule.path,
          nil,
          &message
        )
        defer { ytdlpkit_python_string_free(message) }
        XCTAssertFalse(succeeded)
        XCTAssertEqual(
          ytdlpkit_test_python_initialized(), true,
          "The failed interpreter is retained until process exit.")
        // Do not attempt unsafe reentry or hang a worker if this regresses.
        guard ytdlpkit_test_thread_detached() else {
          XCTFail("Bootstrap failure must release the GIL and detach the initializing thread.")
          return nil
        }
        return message.map { String(cString: $0) }
      }.value
      let originalFailure = try XCTUnwrap(failure)
      XCTAssertTrue(originalFailure.contains("missing the required YoutubeDL API"))
      XCTAssertTrue(originalFailure.contains("Restart the process"))

      // A different native thread must be able to acquire/release the GIL. Bridge
      // retries, including a caller that does not request an error, must not use paths.
      let workerFinished = expectation(description: "GIL handoff and C bridge rejection")
      Thread.detachNewThread {
        XCTAssertTrue(ytdlpkit_test_gil_round_trip())
        for _ in 0..<3 {
          var message: UnsafeMutablePointer<CChar>?
          XCTAssertFalse(
            ytdlpkit_python_initialize("", "", "", "", "", "", nil, &message)
          )
          XCTAssertEqual(message.map { String(cString: $0) }, originalFailure)
          ytdlpkit_python_string_free(message)
          XCTAssertFalse(ytdlpkit_python_initialize("", "", "", "", "", "", nil, nil))
          let result = ytdlpkit_python_execute(nil, 0, nil, nil, nil)
          XCTAssertNil(result.bytes)
          XCTAssertEqual(result.error.map { String(cString: $0) }, originalFailure)
          ytdlpkit_python_result_free(result)
          XCTAssertTrue(ytdlpkit_test_thread_detached())
        }
        workerFinished.fulfill()
      }
      await fulfillment(of: [workerFinished], timeout: 10)

      // Enter through the Swift coordinator, then repeat on the same client and
      // new clients with matching and conflicting identities. No request reaches yt-dlp.
      let firstClient = try YTDLPClient(configuration: YTDLPConfiguration(module: module))
      let firstFailure = await initializationFailure(from: firstClient)
      XCTAssertEqual(firstFailure, originalFailure)
      let validationCount = EmbeddedPythonRuntime.resourceValidationCount
      let repeatedFailure = await initializationFailure(from: firstClient)
      XCTAssertEqual(repeatedFailure, firstFailure)
      for selection in [module, .bundled] {
        let client = try YTDLPClient(configuration: YTDLPConfiguration(module: selection))
        let laterFailure = await initializationFailure(from: client)
        XCTAssertEqual(laterFailure, firstFailure)
      }
      XCTAssertEqual(EmbeddedPythonRuntime.resourceValidationCount, validationCount)

      let unusedRuntime = EmbeddedPythonRuntime()
      do {
        _ = try await unusedRuntime.execute(.search(query: "bootstrap regression", limit: 1))
        XCTFail("An uninitialized runtime must reject execution.")
      } catch let error as YTDLPError {
        guard case .initializationFailed = error else {
          return XCTFail("Expected initializationFailed, got \(error)")
        }
      }
    }

    private func initializationFailure(from client: YTDLPClient) async -> String? {
      do {
        _ = try await client.search("bootstrap regression", limit: 1)
        XCTFail("Expected a terminal bootstrap failure.")
      } catch let error as YTDLPError {
        if case .initializationFailed(let message) = error { return message }
        XCTFail("Expected initializationFailed, got \(error)")
      } catch {
        XCTFail("Expected YTDLPError, got \(error)")
      }
      return nil
    }
  }
#endif
