import Foundation
import XCTest

@testable import YTDLPKit

final class YTDLPClientTests: XCTestCase {
  func testAppleWebKitChallengeProviderIsDisabledByDefaultAndPropagated() async throws {
    let runtime = FixtureRuntime(
      response: RuntimeResponse(sanitizedJSON: try Fixture.data(named: "video-info.json"))
    )
    let client = try YTDLPClient(runtime: runtime)

    _ = try await client.extract(.init(url: URL(string: "https://example.com/video")!))

    let configuration = await runtime.lastConfiguration
    XCTAssertEqual(configuration?.enableAppleWebKitChallengeProvider, false)
  }

  func testAppleWebKitChallengeProviderExplicitOptInIsPropagated() async throws {
    let runtime = FixtureRuntime(
      response: RuntimeResponse(sanitizedJSON: try Fixture.data(named: "video-info.json"))
    )
    let client = try YTDLPClient(
      configuration: .init(enableAppleWebKitChallengeProvider: true),
      runtime: runtime
    )

    _ = try await client.extract(.init(url: URL(string: "https://example.com/video")!))

    let configuration = await runtime.lastConfiguration
    XCTAssertEqual(configuration?.enableAppleWebKitChallengeProvider, true)
  }

  func testCookieFileURLIsPropagatedToRuntime() async throws {
    let runtime = FixtureRuntime(
      response: RuntimeResponse(sanitizedJSON: try Fixture.data(named: "video-info.json"))
    )
    let cookieFileURL = URL(fileURLWithPath: "/private/tmp/ytdlp-cookies.txt")
    let client = try YTDLPClient(
      configuration: .init(cookieFileURL: cookieFileURL),
      runtime: runtime
    )

    _ = try await client.extract(.init(url: URL(string: "https://example.com/video")!))

    let configuration = await runtime.lastConfiguration
    XCTAssertEqual(configuration?.cookieFileURL, cookieFileURL)
  }

  func testRejectsNonFileCookieURL() {
    XCTAssertThrowsError(
      try YTDLPClient(
        configuration: .init(
          cookieFileURL: URL(string: "https://example.com/cookies.txt")
        ))
    ) { error in
      guard case YTDLPError.invalidRequest = error else {
        return XCTFail("Expected invalidRequest, got \(error)")
      }
    }
  }

  func testExtractInitializesOnceAndDecodesFixture() async throws {
    let runtime = FixtureRuntime(
      response: RuntimeResponse(sanitizedJSON: try Fixture.data(named: "video-info.json"))
    )
    let client = try YTDLPClient(runtime: runtime)

    let first = try await client.extract(.init(url: URL(string: "https://example.com/one")!))
    let second = try await client.extract(.init(url: URL(string: "https://example.com/two")!))

    XCTAssertEqual(first.id, "fixture-video")
    XCTAssertEqual(second.id, "fixture-video")
    let initializationCount = await runtime.initializationCount
    let executionCount = await runtime.executionCount
    XCTAssertEqual(initializationCount, 1)
    XCTAssertEqual(executionCount, 2)
  }

  func testSearchDecodesPlaylistEntries() async throws {
    let runtime = FixtureRuntime(
      response: RuntimeResponse(sanitizedJSON: try Fixture.data(named: "search-results.json"))
    )
    let client = try YTDLPClient(runtime: runtime)

    let results = try await client.search("fixture query", limit: 2)

    XCTAssertEqual(results.map(\.id), ["result-one", "result-two"])
    let invocations = await runtime.invocations
    XCTAssertEqual(invocations, [.search(query: "fixture query", limit: 2)])
  }

  func testConcurrentRequestsAreSerializedBeforeRuntime() async throws {
    let runtime = FixtureRuntime(
      response: RuntimeResponse(sanitizedJSON: try Fixture.data(named: "video-info.json")),
      delay: .milliseconds(30)
    )
    let client = try YTDLPClient(runtime: runtime)

    try await withThrowingTaskGroup(of: MediaInfo.self) { group in
      for index in 0..<8 {
        group.addTask {
          try await client.extract(
            .init(url: URL(string: "https://example.com/\(index)")!)
          )
        }
      }
      for try await _ in group {}
    }

    let maximumConcurrentExecutions = await runtime.maximumConcurrentExecutions
    let executionCount = await runtime.executionCount
    XCTAssertEqual(maximumConcurrentExecutions, 1)
    XCTAssertEqual(executionCount, 8)
  }

  func testCancellationIsMappedToTypedError() async throws {
    let runtime = FixtureRuntime(
      response: RuntimeResponse(sanitizedJSON: try Fixture.data(named: "video-info.json")),
      delay: .seconds(5)
    )
    let client = try YTDLPClient(runtime: runtime)
    let task = Task {
      try await client.extract(.init(url: URL(string: "https://example.com/video")!))
    }

    try await Task.sleep(for: .milliseconds(20))
    task.cancel()

    do {
      _ = try await task.value
      XCTFail("Expected cancellation")
    } catch let error as YTDLPError {
      XCTAssertEqual(error, .cancelled)
    }
  }

  func testUnexpectedRuntimeErrorIsMapped() async throws {
    let runtime = FixtureRuntime(
      response: RuntimeResponse(sanitizedJSON: nil),
      failure: FixtureRuntime.RuntimeFailure.fixture
    )
    let client = try YTDLPClient(runtime: runtime)

    do {
      _ = try await client.extract(.init(url: URL(string: "https://example.com/video")!))
      XCTFail("Expected extraction error")
    } catch let error as YTDLPError {
      guard case .extractionFailed = error else {
        return XCTFail("Expected extractionFailed, got \(error)")
      }
    }
  }

  func testPublicClientErrorDoesNotExposeRuntimeSecrets() async throws {
    let runtime = FixtureRuntime(
      response: RuntimeResponse(sanitizedJSON: nil),
      failure: LeakyRuntimeError(
        description: "failed https://media.example/file?signature=secret cookie=session"
      )
    )
    let client = try YTDLPClient(runtime: runtime)

    do {
      _ = try await client.extract(.init(url: URL(string: "https://example.com/video")!))
      XCTFail("Expected extraction error")
    } catch let error as YTDLPError {
      guard case .extractionFailed(let code, let message) = error else {
        return XCTFail("Expected extractionFailed, got \(error)")
      }
      XCTAssertNil(code)
      XCTAssertFalse(message.contains("signature=secret"))
      XCTAssertFalse(message.contains("session"))
      XCTAssertTrue(message.contains("[REDACTED]"))
    }
  }

  func testPublicClientLogEventsAreSanitized() async throws {
    let events = LockedEvents()
    let runtime = FixtureRuntime(
      response: RuntimeResponse(sanitizedJSON: try Fixture.data(named: "video-info.json"))
    )
    let client = try YTDLPClient(
      configuration: .init(logHandler: { events.append($0) }),
      runtime: runtime
    )

    _ = try await client.extract(
      .init(url: URL(string: "https://example.com/video?signature=request-secret")!)
    )

    XCTAssertFalse(events.values.isEmpty)
    XCTAssertFalse(events.values.map(\.message).joined().contains("request-secret"))
  }

  func testCancellingQueuedRequestDoesNotWedgeSerializationGate() async throws {
    let runtime = FixtureRuntime(
      response: RuntimeResponse(sanitizedJSON: try Fixture.data(named: "video-info.json")),
      delay: .milliseconds(60)
    )
    let client = try YTDLPClient(runtime: runtime)
    let first = Task {
      try await client.extract(.init(url: URL(string: "https://example.com/first")!))
    }
    try await Task.sleep(for: .milliseconds(5))
    let queued = Task {
      try await client.extract(.init(url: URL(string: "https://example.com/queued")!))
    }
    queued.cancel()

    _ = try await first.value
    do {
      _ = try await queued.value
      XCTFail("Expected queued request cancellation")
    } catch let error as YTDLPError {
      XCTAssertEqual(error, .cancelled)
    }

    _ = try await client.extract(.init(url: URL(string: "https://example.com/after")!))
    let executionCount = await runtime.executionCount
    XCTAssertEqual(executionCount, 2)
  }

  func testCancellationStressLeavesNoWaitersOrTokenTombstones() async throws {
    let runtime = FixtureRuntime(
      response: RuntimeResponse(sanitizedJSON: try Fixture.data(named: "video-info.json")),
      delay: .milliseconds(100)
    )
    let client = try YTDLPClient(runtime: runtime)
    let first = Task {
      try await client.extract(.init(url: URL(string: "https://example.com/first")!))
    }
    try await Task.sleep(for: .milliseconds(10))

    let queued = (0..<250).map { index in
      Task {
        try await client.extract(
          .init(url: URL(string: "https://example.com/queued-\(index)")!)
        )
      }
    }
    for task in queued {
      task.cancel()
    }

    for task in queued {
      do {
        _ = try await task.value
        XCTFail("Expected cancellation")
      } catch let error as YTDLPError {
        XCTAssertEqual(error, .cancelled)
      }
    }
    _ = try await first.value

    let pendingRequestCount = await client.pendingRequestCount()
    XCTAssertEqual(pendingRequestCount, 0)
    _ = try await client.extract(.init(url: URL(string: "https://example.com/after")!))
    let executionCount = await runtime.executionCount
    XCTAssertEqual(executionCount, 2)
  }

  func testTypedRuntimeErrorAssociatedValuesAreSanitizedBeforeExposure() async throws {
    let runtime = FixtureRuntime(
      response: RuntimeResponse(sanitizedJSON: nil),
      failure: YTDLPError.extractionFailed(
        code: "token=code-secret",
        message: "Authorization: Bearer message-secret\nFile \"/Users/alice/runtime.py\""
      )
    )
    let client = try YTDLPClient(runtime: runtime)

    do {
      _ = try await client.extract(.init(url: URL(string: "https://example.com/video")!))
      XCTFail("Expected extraction error")
    } catch let error as YTDLPError {
      guard case .extractionFailed(let code, let message) = error else {
        return XCTFail("Expected extractionFailed, got \(error)")
      }
      XCTAssertFalse(code?.contains("code-secret") == true)
      XCTAssertFalse(message.contains("message-secret"))
      XCTAssertFalse(message.contains("alice"))
    }
  }

  func testRejectsInvalidRequestsBeforeInitializingRuntime() async throws {
    let runtime = FixtureRuntime(response: RuntimeResponse(sanitizedJSON: Data()))
    let client = try YTDLPClient(runtime: runtime)

    do {
      _ = try await client.search("  ")
      XCTFail("Expected invalid request")
    } catch let error as YTDLPError {
      guard case .invalidRequest = error else {
        return XCTFail("Expected invalidRequest, got \(error)")
      }
    }
    let initializationCount = await runtime.initializationCount
    XCTAssertEqual(initializationCount, 0)
  }
}
