import Foundation

/// Metadata returned by yt-dlp.
public struct MediaInfo: Decodable, Sendable, Equatable {
  public let id: String
  public let title: String
  public let webpageURL: URL?
  public let duration: TimeInterval?
  public let uploader: String?
  public let description: String?
  public let thumbnailURL: URL?
  public let formats: [MediaFormat]
  public let requestedFormats: [MediaFormat]
  public let subtitles: [SubtitleTrack]
  /// Decodable playlist/search entries.
  ///
  /// yt-dlp represents private, deleted, and otherwise unavailable entries as
  /// `null` or partial objects. Those individual entries are intentionally
  /// omitted. The containing top-level `MediaInfo` remains strictly decoded.
  public let entries: [MediaInfo]

  enum CodingKeys: String, CodingKey {
    case id, title, duration, uploader, description, formats, subtitles, entries
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
    description = try container.decodeIfPresent(String.self, forKey: .description)
    thumbnailURL = try container.decodeIfPresent(URL.self, forKey: .thumbnailURL)
    formats = try container.decodeIfPresent([MediaFormat].self, forKey: .formats) ?? []
    requestedFormats =
      try container.decodeIfPresent([MediaFormat].self, forKey: .requestedFormats) ?? []
    entries =
      try container.decodeIfPresent([LossyMediaInfo].self, forKey: .entries)?
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
  }

  /// Chooses the highest-quality format satisfying `selection`.
  public func bestFormat(matching selection: FormatSelection = .any) -> MediaFormat? {
    FormatSelector.best(in: formats, matching: selection)
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
    case width, height
    case framesPerSecond = "fps"
    case totalBitrate = "tbr"
    case videoBitrate = "vbr"
    case audioBitrate = "abr"
    case fileSize = "filesize"
    case approximateFileSize = "filesize_approx"
    case formatNote = "format_note"
    case resolution, language
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
    httpHeaders = try container.decodeIfPresent([String: String].self, forKey: .httpHeaders) ?? [:]
  }

  public var hasVideo: Bool { videoCodec.map { $0 != "none" } ?? false }
  public var hasAudio: Bool { audioCodec.map { $0 != "none" } ?? false }
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
    Int, Int, Double, Double
  ) {
    let preferredCodec =
      selection.preferredVideoCodecPrefix.map {
        format.videoCodec?.hasPrefix($0) == true ? 1 : 0
      } ?? 0
    return (
      preferredCodec,
      format.height ?? 0,
      format.framesPerSecond ?? 0,
      format.totalBitrate ?? format.videoBitrate ?? format.audioBitrate ?? 0
    )
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
