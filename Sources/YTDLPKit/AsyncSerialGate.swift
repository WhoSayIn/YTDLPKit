import Foundation

actor AsyncSerialGate {
  private struct Waiter {
    let token: UUID
    let continuation: CheckedContinuation<Void, any Error>
  }

  private var isLocked = false
  private var waiters: [Waiter] = []

  var waitingCount: Int { waiters.count }

  func acquire(token: UUID) async throws {
    try Task.checkCancellation()
    if !isLocked {
      isLocked = true
      return
    }

    try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<Void, any Error>) in
      waiters.append(Waiter(token: token, continuation: continuation))
    }
  }

  func cancel(token: UUID) {
    if let index = waiters.firstIndex(where: { $0.token == token }) {
      let waiter = waiters.remove(at: index)
      waiter.continuation.resume(throwing: CancellationError())
    }
  }

  func release() {
    if waiters.isEmpty {
      isLocked = false
    } else {
      let waiter = waiters.removeFirst()
      waiter.continuation.resume()
    }
  }
}
