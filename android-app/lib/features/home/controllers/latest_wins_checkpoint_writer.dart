import 'dart:async';

typedef CheckpointDelay = Future<void> Function(Duration duration);

/// Serializes checkpoint writes while retaining only the newest pending value.
///
/// [finalize] closes the queue, drops a pending checkpoint that the final write
/// supersedes, waits for any in-flight checkpoint, and then runs the final write.
class LatestWinsCheckpointWriter<T> {
  LatestWinsCheckpointWriter({
    required this.write,
    this.minimumInterval = const Duration(milliseconds: 250),
    DateTime Function()? now,
    CheckpointDelay? delay,
    this.onError,
  }) : _now = now ?? DateTime.now,
       _delay = delay ?? Future<void>.delayed;

  final Future<void> Function(T value) write;
  final DateTime Function() _now;
  final CheckpointDelay _delay;
  final void Function(Object error, StackTrace stackTrace)? onError;
  final Duration minimumInterval;

  T Function()? _pending;
  Future<void>? _drainFuture;
  DateTime? _lastWriteStartedAt;
  bool _accepting = true;

  void add(T Function() build) {
    if (!_accepting) {
      throw StateError('Checkpoint writer is closed.');
    }
    _pending = build;
    _drainFuture ??= _drain();
  }

  Future<void> barrier() => _drainFuture ?? Future<void>.value();

  Future<R> finalize<R>(Future<R> Function() writeFinal) async {
    if (!_accepting) {
      throw StateError('Checkpoint writer is closed.');
    }
    _accepting = false;
    _pending = null;
    await _drainFuture;
    return writeFinal();
  }

  Future<void> _drain() async {
    try {
      while (_pending != null) {
        final lastStartedAt = _lastWriteStartedAt;
        if (lastStartedAt != null) {
          final elapsed = _now().difference(lastStartedAt);
          final remaining = minimumInterval - elapsed;
          if (remaining > Duration.zero) {
            await _delay(remaining);
          }
        }

        final build = _pending;
        if (build == null) break;
        _pending = null;
        _lastWriteStartedAt = _now();
        try {
          await write(build());
        } catch (error, stackTrace) {
          // Intermediate checkpoints are best-effort. A failed snapshot
          // (e.g. a transient DB busy/locked) is dropped and reported, but
          // must never poison the queue or abort the in-flight generation:
          // the next chunk supersedes it, and the authoritative finalize
          // write surfaces any persistent failure (such as disk full) on its
          // own.
          onError?.call(error, stackTrace);
        }
      }
    } finally {
      _drainFuture = null;
    }
  }
}
