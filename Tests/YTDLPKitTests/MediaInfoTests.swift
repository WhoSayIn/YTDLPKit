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
    XCTAssertEqual(info.chapters.map(\.title), ["Introduction", "Walkthrough", "Wrap-up"])
    XCTAssertEqual(info.chapters.map(\.startTime), [0, 40.5, 91])
    XCTAssertEqual(info.chapters.last?.endTime, 123.5)
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

  func testDecodesOptionalSearchMetadataAndAutomaticCaptions() throws {
    let payload = Data(
      #"""
      {
        "id": "metadata",
        "title": "Metadata",
        "uploader": "Uploader",
        "channel": "Channel",
        "track": "Canonical Track",
        "artists": ["Artist One", "Artist Two"],
        "album": "Album",
        "album_artists": ["Album Artist"],
        "release_year": "2026",
        "track_number": 7,
        "upload_date": "20260831",
        "timestamp": 1788159600,
        "view_count": "1234",
        "like_count": 56,
        "automatic_captions": {
          "en": [{"url":"https://example.com/auto.vtt", "ext":"vtt", "name":"English"}]
        }
      }
      """#.utf8
    )

    let info = try JSONDecoder().decode(MediaInfo.self, from: payload)

    XCTAssertEqual(info.channel, "Channel")
    XCTAssertEqual(info.track, "Canonical Track")
    XCTAssertEqual(info.artists, ["Artist One", "Artist Two"])
    XCTAssertEqual(info.album, "Album")
    XCTAssertEqual(info.albumArtists, ["Album Artist"])
    XCTAssertEqual(info.releaseYear, 2026)
    XCTAssertEqual(info.trackNumber, 7)
    XCTAssertEqual(info.uploadDate, "20260831")
    XCTAssertEqual(info.timestamp, 1_788_159_600)
    XCTAssertEqual(info.viewCount, 1_234)
    XCTAssertEqual(info.likeCount, 56)
    XCTAssertEqual(info.automaticCaptions.map(\.language), ["en"])
  }

  func testOmitsMalformedChaptersWithoutDiscardingValidChapters() throws {
    let payload = Data(
      #"""
      {
        "id": "chapters",
        "title": "Chapters",
        "chapters": [
          {"title":"Intro", "start_time":"0", "end_time":10},
          {"title":"Broken", "start_time":"later", "end_time":20},
          null
        ]
      }
      """#.utf8
    )

    let info = try JSONDecoder().decode(MediaInfo.self, from: payload)

    XCTAssertEqual(info.chapters.map(\.title), ["Intro"])
    XCTAssertEqual(info.chapters.first?.startTime, 0)
    XCTAssertEqual(info.chapters.first?.endTime, 10)
  }

  func testSelectsAudioOnlyFormat() throws {
    let info = try JSONDecoder().decode(
      MediaInfo.self, from: Fixture.data(named: "video-info.json"))
    XCTAssertEqual(info.bestFormat(matching: .init(mediaKind: .audioOnly))?.id, "140")
  }

  func testSelectsOriginalAudioAheadOfHigherBitrateDub() throws {
    let payload = Data(
      #"""
      {
        "id": "multilingual",
        "title": "Multilingual",
        "formats": [
          {
            "format_id": "arabic-dub",
            "url": "https://example.com/arabic.m3u8",
            "vcodec": "none",
            "acodec": "mp4a.40.2",
            "abr": 192,
            "language": "ar",
            "language_preference": -1,
            "format_note": "Dubbed"
          },
          {
            "format_id": "english-original",
            "url": "https://example.com/english.m3u8",
            "vcodec": "none",
            "acodec": "mp4a.40.2",
            "abr": 128,
            "language": "en-US",
            "language_preference": 10,
            "format_note": "Original, Default"
          }
        ]
      }
      """#.utf8
    )

    let info = try JSONDecoder().decode(MediaInfo.self, from: payload)
    let selected = info.bestFormat(matching: .init(mediaKind: .audioOnly))

    XCTAssertEqual(selected?.id, "english-original")
    XCTAssertEqual(selected?.languagePreference, 10)
  }

  func testRecognizesHLSAudioWhenYTDLPOmitsAudioCodec() throws {
    let format = try JSONDecoder().decode(
      MediaFormat.self,
      from: Data(
        #"""
        {
          "format_id": "234-19",
          "url": "https://example.com/original.m3u8",
          "ext": "mp4",
          "protocol": "m3u8_native",
          "vcodec": "none",
          "video_ext": "none",
          "audio_ext": "mp4",
          "resolution": "audio only",
          "language": "en-US",
          "language_preference": 10,
          "format_note": "American English - original (original)"
        }
        """#.utf8
      )
    )

    XCTAssertTrue(format.hasAudio)
    XCTAssertFalse(format.hasVideo)
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
