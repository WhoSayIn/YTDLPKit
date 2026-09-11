# Getting Started

Add YTDLPKit as a package dependency and link its single `YTDLPKit` library
product to an iOS 16 or later target.

## Create a client

Create one long-lived client for a related set of operations:

```swift
import YTDLPKit

let client = try YTDLPClient(configuration: .init())
```

The bundled Apple WebKit JavaScript challenge provider is disabled by default.
Applications that explicitly accept its experimental compatibility and review
surface may opt in before the runtime is initialized:

```swift
let client = try YTDLPClient(
    configuration: .init(enableAppleWebKitChallengeProvider: true)
)
```

Initialization validates the selected resources. The embedded Python runtime is
initialized deterministically on first use and all access remains actor-isolated.

## Extract a URL

```swift
let request = ExtractionRequest(
    url: URL(string: "https://www.youtube.com/watch?v=VIDEO_ID")!
)

do {
    let media = try await client.extract(request)
    print(media.title)
} catch let error as YTDLPError {
    // Present a user-safe message or branch on the typed error category.
    print(error)
}
```

## Search

```swift
let matches = try await client.search("artist song", limit: 20)
```

Search results and extracted metadata share the same immutable model. Availability
and completeness depend on the upstream extractor and source.

`MediaInfo` includes source-neutral music metadata such as track, artists, album,
album artists, release year, and track number, plus presentation metadata such as
channel, upload date, timestamp, view count, like count, chapters, manual subtitles,
and automatic captions when the extractor supplies them. Scalar fields except `id`
and `title` are optional, and music-artist arrays may be empty, because flat search
results are often incomplete.

## Handle stream URLs

A format URL is transient output. Use it promptly for the operation that caused
the extraction together with the format's `httpHeaders`, then discard both. The
headers can contain credentials. Do not persist the entire `MediaInfo` value
without explicitly removing URL- and header-bearing fields.
