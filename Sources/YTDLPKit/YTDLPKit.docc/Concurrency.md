# Concurrency

`YTDLPClient` is an actor. Calls from multiple tasks are safe: the client and a
private process-wide coordinator serialize Python access on an executor that is
not the main actor.

```swift
async let first = client.extract(ExtractionRequest(url: firstURL))
async let second = client.extract(ExtractionRequest(url: secondURL))
let values = try await [first, second]
```

The caller may create concurrent tasks, but Python operations execute in a
defined serial order. Each request receives an independent yt-dlp options
dictionary, logger, timeout, and cancellation state.

Cancellation is cooperative. YTDLPKit checks cancellation before and after the
Python call and through an upstream hook where safe. Some extractor work cannot
be interrupted immediately; configure finite network timeouts and do not block
the main actor while awaiting a result.
