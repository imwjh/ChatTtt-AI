import 'dart:io';

/// A non-blocking exclusive advisory lock on a fixed lease file.
///
/// The lock is a POSIX record lock, which is owned by the process rather than
/// by the descriptor that took it. That scope is deliberate. A descriptor is
/// not closed when its isolate goes away: a Flutter engine restart, whether
/// from a hot restart or from Android recreating the activity, leaves the
/// previous root isolate's descriptor open inside the surviving process. A
/// description-scoped `flock` would therefore keep the incoming engine locked
/// out of its own data until the process itself dies, turning a recoverable
/// restart into a dead app.
///
/// The cost of process ownership is that this lock alone cannot separate two
/// isolates inside one process, and that closing any descriptor of the file
/// drops the lock for the whole process. Both are covered by the owner marker
/// and its liveness probe in `RestoreBusinessLease`, which is also what makes
/// the marker mandatory rather than an optimization.
final class RestoreLeaseLock {
  RestoreLeaseLock._(this._handle);

  final RandomAccessFile _handle;
  var _released = false;

  /// Takes the lock without waiting.
  ///
  /// Returns null when another process holds it. Every other failure is
  /// reported as a [FileSystemException].
  static Future<RestoreLeaseLock?> tryAcquire(File file) async {
    final handle = await file.open(mode: FileMode.append);
    try {
      await handle.lock(FileLock.exclusive);
    } on FileSystemException catch (error) {
      await handle.close();
      if (_isUnavailable(error)) return null;
      rethrow;
    } catch (_) {
      await handle.close();
      rethrow;
    }
    return RestoreLeaseLock._(handle);
  }

  /// Releases the lock. Repeated calls are harmless.
  Future<void> release() async {
    if (_released) return;
    _released = true;
    try {
      await _handle.unlock();
    } finally {
      await _handle.close();
    }
  }

  static bool _isUnavailable(FileSystemException error) {
    final code = error.osError?.errorCode;
    if (code == null) return false;
    if (Platform.isWindows) return code == 32 || code == 33;
    return code == 11 || code == 13 || code == 35;
  }
}
