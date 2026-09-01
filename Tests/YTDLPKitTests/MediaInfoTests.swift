import Foundation
import XCTest

@testable import YTDLPKit

final class MediaInfoTests: XCTestCase {
  func testDecodesRecordedMetadataAndNestedRequestedFormats() throws {
    let info = try JSONDecoder().decode(
      MediaInfo.self, from: Fixture.data(named: "video-info.json"))

    XCTAssertEqual(info.id, "fixture-video")
    XCTAssertEqual(info.title, "Fixture Video")
    XCTAssertEqual(info.duration, 123.5)
    XCTAssertEqual(info.formats.count, 4)
    XCTAssertEqual(info.requestedFormats.map(\.id), ["137", "140"])
    XCTAssertEqual(info.subtitles.map(\.language), ["en", "tr"])
    XCTAssertEqual(info.formats.first(where: { $0.id == "137" })?.height, 1080)
    XCTAssertEqual(info.formats.first(where: { $0.id == "137" })?.fileSize, 10_485_760)
    XCTAssertEqual(info.formats.first(where: { $0.id == "137" })?.resolution, "1920x1080")
    XCTAssertEqual(info.formats.first(where: { $0.id == "137" })?.language, "en-US")
    XCTAssertEqual(
      info.formats.first(where: { $0.id == "137" })?.httpHeaders,
      ["User-Agent": "FixtureAgent/1.0", "Referer": "https://www.youtube.com/"]
    )
    XCTAssertEqual(info.formats.first(where: { $0.id == "140" })?.httpHeaders, [:])
  }

  func testSelectsPreferredH264VideoWithinHeightLimit() throws {
    let info = try JSONDecoder().decode(
      MediaInfo.self, from: Fixture.data(named: "video-info.json"))

    let selected = info.bestFormat(
      matching: FormatSelection(
        mediaKind: .videoOnly,
        maximumHeight: 1080,
        preferredVideoCodecPrefix: "avc1"
      )
    )

    XCTAssertEqual(selected?.id, "137")
  }

  func testSelectsAudioOnlyFormat() throws {
    let info = try JSONDecoder().decode(
      MediaInfo.self, from: Fixture.data(named: "video-info.json"))
    XCTAssertEqual(info.bestFormat(matching: .init(mediaKind: .audioOnly))?.id, "140")
  }

  func testMalformedFixtureProducesTypedDecodingFailure() throws {
    let response = RuntimeResponse(sanitizedJSON: try Fixture.data(named: "malformed.json"))
    XCTAssertThrowsError(try RuntimeResponseDecoder.decodeMediaInfo(from: response)) { error in
      guard case YTDLPError.decodingFailed = error else {
        return XCTFail("Expected decodingFailed, got \(error)")
      }
    }
  }

  func testPlaylistOmitsNullAndUnavailableEntriesButKeepsValidEntries() throws {
    let payload = Data(
      #"""
      {
        "id": "playlist",
        "title": "Fixture Playlist",
        "entries": [
          null,
          {"_type":"unavailable", "title":"Private video"},
          {"id":"available", "title":"Available video"}
        ]
      }
      """#.utf8
    )

    let info = try JSONDecoder().decode(MediaInfo.self, from: payload)

    XCTAssertEqual(info.entries.map(\.id), ["available"])
  }

  func testDirectSearchArrayOmitsUnavailableEntries() throws {
    let response = RuntimeResponse(
      sanitizedJSON: Data(
        #"""
        [null, {"title":"Unavailable"}, {"id":"result", "title":"Result"}]
        """#.utf8
      )
    )

    XCTAssertEqual(
      try RuntimeResponseDecoder.decodeSearchResults(from: response).map(\.id), ["result"])
  }

  func testMalformedTopLevelMetadataStillFailsStrictly() {
    let payload = Data(#"{"entries":[null,{"id":"entry","title":"Entry"}]}"#.utf8)

    XCTAssertThrowsError(try JSONDecoder().decode(MediaInfo.self, from: payload))
  }

  func testNonFiniteAndOutOfRangeIntegerConversionsReturnNil() throws {
    XCTAssertNil(SafeIntegerConversion.int(.nan))
    XCTAssertNil(SafeIntegerConversion.int(.infinity))
    XCTAssertNil(SafeIntegerConversion.int(-.infinity))
    XCTAssertNil(SafeIntegerConversion.int(1e300))
    XCTAssertNil(SafeIntegerConversion.int(-1e300))
    XCTAssertNil(SafeIntegerConversion.int64(.nan))
    XCTAssertNil(SafeIntegerConversion.int64(.infinity))
    XCTAssertNil(SafeIntegerConversion.int64(-.infinity))
    XCTAssertNil(SafeIntegerConversion.int64(1e300))
    XCTAssertNil(SafeIntegerConversion.int64(-1e300))

    let format = try JSONDecoder().decode(
      MediaFormat.self,
      from: Data(#"{"format_id":"huge","width":1e300,"filesize":-1e300}"#.utf8)
    )
    XCTAssertNil(format.width)
    XCTAssertNil(format.fileSize)
  }
}
