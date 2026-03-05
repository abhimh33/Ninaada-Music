import 'dart:async';

// ================================================================
//  ASYNC MUTEX — FIFO operation-chaining lock
// ================================================================
//
//  Guarantees that only ONE async queue-mutation runs at a time.
//  Each call to [protect] chains behind the previous one:
//
//    ┌─ protect(loadQueue) ──────────┐
//    │                               │  ← runs first
//    └───────────────────────────────┘
//      ┌─ protect(insertNext) ──────┐
//      │                            │  ← waits for loadQueue, then runs
//      └────────────────────────────┘
//        ┌─ protect(appendToQueue) ─┐
//        │                          │  ← waits for insertNext
//        └──────────────────────────┘
//
//  Dart's single-threaded event loop means there are no true
//  data races, but INTERLEAVED async operations can corrupt
//  shared mutable state (_songs + _playlist). The mutex serializes
//  these so each operation sees a consistent snapshot.
//
//  Thread-safe by design:
//    • Previous errors do NOT block subsequent operations
//    • The chain is always released in `finally`
//    • No starvation — strict FIFO ordering
// ================================================================

class AsyncMutex {
  Future<void> _chain = Future.value();

  /// Whether an operation is currently executing under the lock.
  bool _locked = false;
  bool get isLocked => _locked;

  /// Execute [action] under exclusive lock.
  ///
  /// If another operation is in progress, this call suspends until
  /// it completes, then runs [action]. Operations execute in FIFO order.
  ///
  /// Errors from [action] propagate to the caller but do NOT block
  /// subsequent operations.
  Future<T> protect<T>(Future<T> Function() action) async {
    final prev = _chain;
    final completer = Completer<void>();
    _chain = completer.future;

    try {
      await prev;
    } catch (_) {
      // Ignore errors from previous operations — they already
      // propagated to their own callers.
    }

    _locked = true;
    try {
      return await action();
    } finally {
      _locked = false;
      completer.complete();
    }
  }
}
