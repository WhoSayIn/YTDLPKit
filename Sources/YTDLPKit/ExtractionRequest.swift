import Foundation

/// A metadata-only extraction request.
public struct ExtractionRequest: Sendable, Equatable {
  public let url: URL
  public let includePlaylists: Bool

  public init(url: URL, includePlaylists: Bool = false) {
    self.url = url
    self.includePlaylists = includePlaylists
  }
}
