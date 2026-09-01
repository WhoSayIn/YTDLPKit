import Foundation
import XCTest
import YTDLPKit

final class LiveIntegrationTests: XCTestCase {
  /// Runs only when explicitly enabled because it contacts YouTube and depends
  /// on the bundled Python/yt-dlp runtime being available on the test host.
  func testLiveMetadataExtractionAndSearch() async throws {
    #if YTDLPKIT_LIVE_TESTS
      let liveTestsEnabled = true
    #else
      let liveTestsEnabled = ProcessInfo.processInfo.environment["YTDLPKIT_LIVE_TESTS"] == "1"
    #endif
    try XCTSkipUnless(
      liveTestsEnabled,
      "Set YTDLPKIT_LIVE_TESTS=1 or compile with -DYTDLPKIT_LIVE_TESTS to run network-dependent integration tests."
    )

    let client = try YTDLPClient(
      configuration: .init(networkTimeout: .seconds(45))
    )
    let results = try await client.search("YouTube Creators", limit: 5)
    XCTAssertFalse(results.isEmpty)
    XCTAssertTrue(results.allSatisfy { !$0.id.isEmpty && !$0.title.isEmpty })

    let candidate = try XCTUnwrap(results.first)
    let candidateURL = try XCTUnwrap(
      candidate.webpageURL ?? URL(string: "https://www.youtube.com/watch?v=\(candidate.id)")
    )
    let extracted = try await client.extract(.init(url: candidateURL))
    XCTAssertFalse(extracted.id.isEmpty)
    XCTAssertFalse(extracted.title.isEmpty)
    XCTAssertFalse(extracted.formats.isEmpty)
  }
}
