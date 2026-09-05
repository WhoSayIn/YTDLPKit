import Foundation

/// Metadata returned by yt-dlp.
public struct MediaInfo: Decodable, Sendable, Equatable {
  public let id: String
  public let title: String
  public let webpageURL: URL?
  public let duration: TimeInterval?
  public let uploader: String?
  public let channel: String?
  public let album: String?
  public let uploadDate: String?
  public let timestamp: TimeInterval?
  public let viewCount: Int64?
  public let likeCount: Int64?
  public let description: String?
  public let thumbnailURL: URL?
  public let formats: [MediaFormat]
  public let requestedFormats: [MediaFormat]
  public let subtitles: [SubtitleTrack]
  public let automaticCaptions: [SubtitleTrack]
  public let chapters: [MediaChapter]
  /// Decodable playlist/search entries.
  ///
  /// yt-dlp represents private, deleted, and otherwise unavailable entries as
  /// `null` or partial objects. Those individual entries are intentionally
  /// omitted. The containing top-level `MediaInfo` remains strictly decoded.
  public let entries: [MediaInfo]

  enum CodingKeys: String, CodingKey {
    case id, title, duration, uploader, channel, album, description, formats, subtitles, chapters,
      entries
    case timestamp
    case uploadDate = "upload_date"
    case viewCount = "view_count"
    case likeCount = "like_count"
    case automaticCaptions = "automatic_captions"
    case webpageURL = "webpage_url"
    case thumbnailURL = "thumbnail"
    case requestedFormats = "requested_formats"
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    title = try container.decode(String.self, forKey: .title)
    webpageURL = try container.decodeIfPresent(URL.self, forKey: .webpageURL)
    duration = try container.decodeLossyDoubleIfPresent(forKey: .duration)
    uploader = try container.decodeIfPresent(String.self, forKey: .uploader)
    channel = try container.decodeIfPresent(String.self, forKey: .channel)
    album = try container.decodeIfPresent(String.self, forKey: .album)
    uploadDate = try container.decodeIfPresent(String.self, forKey: .uploadDate)
    timestamp = try container.decodeLossyDoubleIfPresent(forKey: .timestamp)
    viewCount = try container.decodeLossyInt64IfPresent(forKey: .viewCount)
    likeCount = try container.decodeLossyInt64IfPresent(forKey: .likeCount)
    description = try container.decodeIfPresent(String.self, forKey: .description)
    thumbnailURL = try container.decodeIfPresent(URL.self, forKey: .thumbnailURL)
    formats = try container.decodeIfPresent([MediaFormat].self, forKey: .formats) ?? []
    requestedFormats =
      try container.decodeIfPresent([MediaFormat].self, forKey: .requestedFormats) ?? []
    entries =
      try container.decodeIfPresent([LossyMediaInfo].self, forKey: .entries)?
      .compactMap(\.value) ?? []
    chapters =
      try container.decodeIfPresent([LossyMediaChapter].self, forKey: .chapters)?
      .compactMap(\.value) ?? []

    let subtitleGroups =
      try container.decodeIfPresent(
        [String: [SubtitlePayload]].self,
        forKey: .subtitles
      ) ?? [:]
    subtitles = subtitleGroups.flatMap { language, payloads in
      payloads.map { SubtitleTrack(language: language, payload: $0) }
    }.sorted {
      ($0.language, $0.name ?? "", $0.format ?? "") < ($1.language, $1.name ?? "", $1.format ?? "")
    }

    let automaticCaptionGroups =
      try container.decodeIfPresent(
        [String: [SubtitlePayload]].self,
        forKey: .automaticCaptions
      ) ?? [:]
    automaticCaptions = automaticCaptionGroups.flatMap { language, payloads in
      payloads.map { SubtitleTrack(language: language, payload: $0) }
    }.sorted {
      ($0.language, $0.name ?? "", $0.format ?? "") < ($1.language, $1.name ?? "", $1.format ?? "")
    }
  }

  /// Chooses the highest-quality format satisfying `selection`.
  public func bestFormat(matching selection: FormatSelection = .any) -> MediaFormat? {
    FormatSelector.best(in: formats, matching: selection)
  }
}

/// A chapter boundary reported by yt-dlp for a media item.
public struct MediaChapter: Decodable, Sendable, Equatable {
  public let title: String
  public let startTime: TimeInterval
  public let endTime: TimeInterval

  enum CodingKeys: String, CodingKey {
    case title
    case startTime = "start_time"
    case endTime = "end_time"
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    title = try container.decode(String.self, forKey: .title)
    guard
      let startTime = try container.decodeLossyDoubleIfPresent(forKey: .startTime),
      let endTime = try container.decodeLossyDoubleIfPresent(forKey: .endTime)
    else {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: container.codingPath,
          debugDescription: "Chapter start_time and end_time must be numeric."
        )
      )
    }
    self.startTime = startTime
    self.endTime = endTime
  }
}

/// A stream format. `streamURL` is temporary and must not be persisted.
public struct MediaFormat: Decodable, Sendable, Equatable {
  public let id: String
  public let streamURL: URL?
  public let extensionName: String?
  public let protocolName: String?
  public let videoCodec: String?
  public let audioCodec: String?
  public let videoExtensionName: String?
  public let audioExtensionName: String?
  public let width: Int?
  public let height: Int?
  public let framesPerSecond: Double?
  public let totalBitrate: Double?
  public let videoBitrate: Double?
  public let audioBitrate: Double?
  public let fileSize: Int64?
  public let formatNote: String?
  public let resolution: String?
  public let language: String?
  /// yt-dlp's relative preference for this format's audio language.
  public let languagePreference: Int?
  /// Request headers required when consuming `streamURL`.
  ///
  /// Header values may contain credentials and must not be logged or persisted.
  public let httpHeaders: [String: String]

  enum CodingKeys: String, CodingKey {
    case id = "format_id"
    case streamURL = "url"
    case extensionName = "ext"
    case protocolName = "protocol"
    case videoCodec = "vcodec"
    case audioCodec = "acodec"
    case videoExtensionName = "video_ext"
    case audioExtensionName = "audio_ext"
    case width, height
    case framesPerSecond = "fps"
    case totalBitrate = "tbr"
    case videoBitrate = "vbr"
    case audioBitrate = "abr"
    case fileSize = "filesize"
    case approximateFileSize = "filesize_approx"
    case formatNote = "format_note"
    case resolution, language
    case languagePreference = "language_preference"
    case httpHeaders = "http_headers"
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    streamURL = try container.decodeIfPresent(URL.self, forKey: .streamURL)
    extensionName = try container.decodeIfPresent(String.self, forKey: .extensionName)
    protocolName = try container.decodeIfPresent(String.self, forKey: .protocolName)
    videoCodec = try container.decodeIfPresent(String.self, forKey: .videoCodec)
    audioCodec = try container.decodeIfPresent(String.self, forKey: .audioCodec)
    videoExtensionName = try container.decodeIfPresent(String.self, forKey: .videoExtensionName)
    audioExtensionName = try container.decodeIfPresent(String.self, forKey: .audioExtensionName)
    width = try container.decodeLossyIntIfPresent(forKey: .width)
    height = try container.decodeLossyIntIfPresent(forKey: .height)
    framesPerSecond = try container.decodeLossyDoubleIfPresent(forKey: .framesPerSecond)
    totalBitrate = try container.decodeLossyDoubleIfPresent(forKey: .totalBitrate)
    videoBitrate = try container.decodeLossyDoubleIfPresent(forKey: .videoBitrate)
    audioBitrate = try container.decodeLossyDoubleIfPresent(forKey: .audioBitrate)
    fileSize =
      try container.decodeLossyInt64IfPresent(forKey: .fileSize)
      ?? container.decodeLossyInt64IfPresent(forKey: .approximateFileSize)
    formatNote = try container.decodeIfPresent(String.self, forKey: .formatNote)
    resolution = try container.decodeIfPresent(String.self, forKey: .resolution)
    language = try container.decodeIfPresent(String.self, forKey: .language)
    languagePreference = try container.decodeLossyIntIfPresent(forKey: .languagePreference)
    httpHeaders = try container.decodeIfPresent([String: String].self, forKey: .httpHeaders) ?? [:]
  }

  public var hasVideo: Bool {
    videoCodec.map { $0 != "none" }
      ?? videoExtensionName.map { $0 != "none" }
      ?? false
  }

  public var hasAudio: Bool {
    audioCodec.map { $0 != "none" }
      ?? audioExtensionName.map { $0 != "none" }
      ?? false
  }
}

/// A subtitle or caption resource.
public struct SubtitleTrack: Sendable, Equatable {
  public let language: String
  public let name: String?
  public let format: String?
  public let url: URL

  fileprivate init(language: String, payload: SubtitlePayload) {
    self.language = language
    name = payload.name
    format = payload.extensionName
    url = payload.url
  }
}

/// Constraints used when selecting a format from `MediaInfo.formats`.
public struct FormatSelection: Sendable, Equatable {
  public enum MediaKind: Sendable, Equatable {
    case any
    case audioOnly
    case videoOnly
    case audiovisual
  }

  public var mediaKind: MediaKind
  public var maximumHeight: Int?
  public var preferredVideoCodecPrefix: String?

  public init(
    mediaKind: MediaKind = .any,
    maximumHeight: Int? = nil,
    preferredVideoCodecPrefix: String? = nil
  ) {
    self.mediaKind = mediaKind
    self.maximumHeight = maximumHeight
    self.preferredVideoCodecPrefix = preferredVideoCodecPrefix
  }

  public static let any = FormatSelection()
}

private struct SubtitlePayload: Decodable {
  let url: URL
  let extensionName: String?
  let name: String?

  enum CodingKeys: String, CodingKey {
    case url
    case extensionName = "ext"
    case name
  }
}

struct LossyMediaInfo: Decodable {
  let value: MediaInfo?

  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      value = nil
      return
    }
    value = try? container.decode(MediaInfo.self)
  }
}

private struct LossyMediaChapter: Decodable {
  let value: MediaChapter?

  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      value = nil
      return
    }
    value = try? container.decode(MediaChapter.self)
  }
}

private enum FormatSelector {
  static func best(in formats: [MediaFormat], matching selection: FormatSelection) -> MediaFormat? {
    formats
      .filter { format in
        guard format.streamURL != nil else { return false }
        if let maximumHeight = selection.maximumHeight,
          let height = format.height,
          height > maximumHeight
        {
          return false
        }
        switch selection.mediaKind {
        case .any: return true
        case .audioOnly: return format.hasAudio && !format.hasVideo
        case .videoOnly: return format.hasVideo && !format.hasAudio
        case .audiovisual: return format.hasVideo && format.hasAudio
        }
      }
      .max { lhs, rhs in
        score(lhs, selection: selection) < score(rhs, selection: selection)
      }
  }

  private static func score(_ format: MediaFormat, selection: FormatSelection) -> (
    Int, Int, Int, Double, Double
  ) {
    let preferredCodec =
      selection.preferredVideoCodecPrefix.map {
        format.videoCodec?.hasPrefix($0) == true ? 1 : 0
      } ?? 0
    return (
      audioLanguageScore(format, selection: selection),
      preferredCodec,
      format.height ?? 0,
      format.framesPerSecond ?? 0,
      format.totalBitrate ?? format.videoBitrate ?? format.audioBitrate ?? 0
    )
  }

  private static func audioLanguageScore(
    _ format: MediaFormat,
    selection: FormatSelection
  ) -> Int {
    guard selection.mediaKind == .audioOnly || selection.mediaKind == .audiovisual else {
      return 0
    }

    let note = format.formatNote?.lowercased() ?? ""
    var score = format.languagePreference ?? 0
    if note.contains("original") { score += 100 }
    if note.contains("default") { score += 50 }
    if note.contains("dubbed") { score -= 100 }
    return score
  }
}

extension KeyedDecodingContainer {
  fileprivate func decodeLossyDoubleIfPresent(forKey key: Key) throws -> Double? {
    if let value = try? decode(Double.self, forKey: key) { return value }
    if let value = try? decode(Int.self, forKey: key) { return Double(value) }
    if let value = try? decode(String.self, forKey: key) { return Double(value) }
    return nil
  }

  fileprivate func decodeLossyIntIfPresent(forKey key: Key) throws -> Int? {
    if let value = try? decode(Int.self, forKey: key) { return value }
    if let value = try? decode(Double.self, forKey: key) {
      return SafeIntegerConversion.int(value)
    }
    if let value = try? decode(String.self, forKey: key) { return Int(value) }
    return nil
  }

  fileprivate func decodeLossyInt64IfPresent(forKey key: Key) throws -> Int64? {
    if let value = try? decode(Int64.self, forKey: key) { return value }
    if let value = try? decode(Double.self, forKey: key) {
      return SafeIntegerConversion.int64(value)
    }
    if let value = try? decode(String.self, forKey: key) { return Int64(value) }
    return nil
  }
}

enum SafeIntegerConversion {
  static func int(_ value: Double) -> Int? {
    guard value.isFinite,
      value >= Double(Int.min),
      value < Double(Int.max)
    else { return nil }
    return Int(value)
  }

  static func int64(_ value: Double) -> Int64? {
    guard value.isFinite,
      value >= Double(Int64.min),
      value < Double(Int64.max)
    else { return nil }
    return Int64(value)
  }
}
