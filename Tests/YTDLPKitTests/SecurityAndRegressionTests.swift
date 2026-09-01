import Foundation
import XCTest

@testable import YTDLPKit

final class SecurityAndRegressionTests: XCTestCase {
  func testLogsRedactSignedURLsCookiesAndCredentials() {
    let event = YTDLPLogEvent(
      level: .error,
      message:
        "failed https://media.example/video?signature=abc&token=xyz cookie=session credential=hunter2"
    )

    XCTAssertFalse(event.message.contains("abc"))
    XCTAssertFalse(event.message.contains("xyz"))
    XCTAssertFalse(event.message.contains("session"))
    XCTAssertFalse(event.message.contains("hunter2"))
    XCTAssertTrue(event.message.contains("[REDACTED]"))
  }

  func testErrorDescriptionsRedactRuntimeDetails() {
    let error = YTDLPError.extractionFailed(
      code: "network",
      message: "Authorization: Bearer-secret https://media.example/file?sig=secret"
    )

    XCTAssertFalse(error.description.contains("Bearer-secret"))
    XCTAssertFalse(error.description.contains("sig=secret"))
  }

  func testAdversarialMultilineDiagnosticsAreRedacted() {
    let diagnostic = #"""
      Authorization: Bearer header.payload.signature
      Cookie: session=super-secret; refresh=also-secret
      {"password":"quoted secret", "api_key":"json-secret", "token":"line-secret"}
      Traceback (most recent call last):
        File "/Users/alice/Library/Application Support/YTDLPKit/runtime.py", line 42
        File '/private/var/mobile/Containers/Data/Application/UUID/script.py', line 7
      """#

    let redacted = SensitiveDataRedactor.redact(diagnostic)

    for secret in [
      "header.payload.signature", "super-secret", "also-secret", "quoted secret",
      "json-secret", "line-secret", "alice", "Containers/Data/Application",
    ] {
      XCTAssertFalse(redacted.contains(secret), "Leaked \(secret): \(redacted)")
    }
    XCTAssertTrue(redacted.contains("[REDACTED]"))
    XCTAssertTrue(redacted.contains("[REDACTED_PATH]"))
  }

  /// Regression coverage for bridges which fail before producing stdout.
  func testNoStdoutMapsToSubprocessFailureWithoutLeakingStderrURL() {
    let response = RuntimeResponse(
      sanitizedJSON: nil,
      diagnostic: "ERROR https://media.example/file?signature=secret",
      exitCode: 1
    )

    XCTAssertThrowsError(try RuntimeResponseDecoder.decodeMediaInfo(from: response)) { error in
      guard case YTDLPError.subprocessFailed(let code, let message) = error else {
        return XCTFail("Expected subprocessFailed, got \(error)")
      }
      XCTAssertEqual(code, 1)
      XCTAssertFalse(message.contains("signature=secret"))
      XCTAssertTrue(message.contains("[REDACTED]"))
      XCTAssertFalse(String(describing: error).contains("signature=secret"))
    }
  }

  func testEmptyDirectRuntimeOutputIsMalformedOutput() {
    XCTAssertThrowsError(
      try RuntimeResponseDecoder.decodeMediaInfo(from: RuntimeResponse(sanitizedJSON: nil))
    ) { error in
      guard case YTDLPError.malformedOutput = error else {
        return XCTFail("Expected malformedOutput, got \(error)")
      }
    }
  }
}
