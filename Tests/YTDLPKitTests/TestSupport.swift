import Foundation

@testable import YTDLPKit

enum Fixture {
  static func data(named name: String) throws -> Data {
    let testDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let url =
      testDirectory
      .deletingLastPathComponent()
      .appendingPathComponent("Fixtures", isDirectory: true)
      .appendingPathComponent(name)
    return try Data(contentsOf: url)
  }
}

actor FixtureRuntime: YTDLPRuntime {
  enum RuntimeFailure: Error { case fixture }

  private let response: RuntimeResponse
  private let delay: Duration
  private let failure: (any Error)?
  private(set) var initializationCount = 0
  private(set) var lastConfiguration: RuntimeConfiguration?
  private(set) var executionCount = 0
  private(set) var activeExecutions = 0
  private(set) var maximumConcurrentExecutions = 0
  private(set) var invocations: [RuntimeInvocation] = []

  init(
    response: RuntimeResponse,
    delay: Duration = .zero,
    failure: (any Error)? = nil
  ) {
    self.response = response
    self.delay = delay
    self.failure = failure
  }

  func initialize(configuration: RuntimeConfiguration) async throws {
    initializationCount += 1
    lastConfiguration = configuration
  }

  func execute(_ invocation: RuntimeInvocation) async throws -> RuntimeResponse {
    executionCount += 1
    invocations.append(invocation)
    activeExecutions += 1
    maximumConcurrentExecutions = max(maximumConcurrentExecutions, activeExecutions)
    defer { activeExecutions -= 1 }
    if delay > .zero { try await Task.sleep(for: delay) }
    if let failure { throw failure }
    return response
  }
}

struct LeakyRuntimeError: Error, CustomStringConvertible {
  let description: String
}

final class LockedEvents: @unchecked Sendable {
  private let lock = NSLock()
  private var storage: [YTDLPLogEvent] = []

  func append(_ event: YTDLPLogEvent) {
    lock.lock()
    storage.append(event)
    lock.unlock()
  }

  var values: [YTDLPLogEvent] {
    lock.lock()
    defer { lock.unlock() }
    return storage
  }
}
