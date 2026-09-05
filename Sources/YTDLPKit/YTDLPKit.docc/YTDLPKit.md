# ``YTDLPKit``

Extract media metadata through a typed, concurrency-safe Swift interface to a
pinned yt-dlp runtime.

## Overview

Create a client, then submit a URL or search query from an asynchronous context:

```swift
let client = try YTDLPClient(configuration: .init())
let request = ExtractionRequest(url: mediaURL)
let media = try await client.extract(request)
```

``YTDLPClient`` is an actor and exclusively coordinates Python access. Results
are immutable `Sendable` Swift values. The public API never exposes PythonKit or
Python objects.

YTDLPKit performs metadata-only operations. It does not download, transcode,
mux, play, or persist media.

> Important: Extracted stream URLs can be signed and short-lived. Consume them
> promptly and do not store or log them.

## Topics

### Getting started

- <doc:GettingStarted>
- ``YTDLPClient``
- ``YTDLPConfiguration``

### Requests and results

- ``ExtractionRequest``
- ``MediaInfo``
- ``MediaFormat``
- ``MediaChapter``
- ``SubtitleTrack``

Audio format selection uses yt-dlp's language preference and original/default
format annotations before comparing quality, so a dubbed rendition does not
replace the source audio merely because it has a higher bitrate.

### Diagnostics

- ``YTDLPError``
- ``YTDLPLogEvent``

### Design and safety

- <doc:Concurrency>
- <doc:SecurityAndPrivacy>
- <doc:LocalModuleSelection>
