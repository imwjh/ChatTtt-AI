import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import 'restore_durability.dart';
import 'restore_lease_lock.dart';

/// Thrown when another business process or this Dart process already owns the
/// restore business lease.
final class RestoreBusinessLeaseUnavailable implements Exception {
  const RestoreBusinessLeaseUnavailable(this.path, {this.cause});

  final String path;
  final FileSystemException? cause;

  @override
  String toString() => 'Restore business lease is unavailable: $path';
}

/// A process-lifetime lease preventing restore cutover from overlapping an
/// already running business process.
///
/// The operating-system advisory lock is non-blocking. The isolate registry
/// and the process owner marker are also required: the lock only proves that
/// no other open file description holds the lease, while a recreated Android
/// engine puts a second root isolate inside this same process.
final class RestoreBusinessLease {
  RestoreBusinessLease._({
    required this.lockFile,
    required this.instanceId,
    required this.processId,
    required this._processOwnerFile,
    required this._processOwnerProbe,
    required this._registryKey,
    required this._lock,
  });

  static const leaseDirectoryName = '.kelivo_business_lease';
  static const lockFileName = 'lease.lock';
  static const _processOwnerPrefix = 'owner_';

  static const _contentionPoll = Duration(milliseconds: 100);

  /// How long a predecessor engine inside this same OS process is waited out
  /// before the lease is reported unavailable.
  static const _defaultOwnerGrace = Duration(seconds: 8);

  /// How long a lock held by another OS process is waited out.
  ///
  /// No platform this app ships on lets a user hold two instances open on
  /// purpose: a phone cannot run the app twice, and the desktop runners hand a
  /// second launch to the window that is already open. Contention here is
  /// therefore a previous process still being torn down, and it disappears the
  /// moment that process dies.
  static const _defaultForeignLockGrace = Duration(seconds: 5);

  /// How many consecutive silent probes retire a same-process owner marker.
  ///
  /// One silent probe is not proof of death: a device returning to the
  /// foreground can stall the outgoing isolate past the probe timeout, and
  /// retiring a live owner would let two engines open the business data.
  static const _ownerDeathConfirmations = 3;

  static final Map<String, RestoreBusinessLease?> _processLeases = {};

  final File lockFile;
  final String instanceId;

  /// Stable native process identity captured when this lease was acquired.
  ///
  /// Unlike [instanceId], reacquiring the lease in the same OS process keeps
  /// this value unchanged. It is intentionally part of cold-restart proof.
  final int processId;
  final File _processOwnerFile;
  final _ProcessOwnerProbe _processOwnerProbe;
  final String _registryKey;
  RestoreLeaseLock? _lock;

  bool get isClosed => _lock == null;

  /// Acquires the fixed AppData business lease.
  ///
  /// Contention is waited out before it is reported: a predecessor inside this
  /// same OS process for at most [sameProcessOwnerGrace], and a lock held by
  /// another process for at most [foreignLockGrace]. Android recreates the
  /// activity, and with it the Flutter engine and its root isolate, while the
  /// outgoing engine is still shutting down inside the surviving process, and
  /// any platform can start the app while its previous process is still dying.
  /// Neither is a second app instance the user could close.
  ///
  /// [RestoreBusinessLeaseUnavailable] means that the exact lease is still
  /// held once those windows elapsed. Other filesystem or durability failures
  /// are propagated unchanged.
  static Future<RestoreBusinessLease> acquire({
    required Directory appDataDirectory,
    RestoreDurability? durability,
    Duration? sameProcessOwnerGrace,
    Duration? foreignLockGrace,
  }) async {
    final ownerGrace = sameProcessOwnerGrace ?? _defaultOwnerGrace;
    final lockGrace = foreignLockGrace ?? _defaultForeignLockGrace;
    final leaseDirectory = Directory(
      p.join(appDataDirectory.path, leaseDirectoryName),
    );
    final lockFile = File(p.join(leaseDirectory.path, lockFileName));
    final registryKey = p.normalize(p.absolute(lockFile.path));
    if (_processLeases.containsKey(registryKey)) {
      throw RestoreBusinessLeaseUnavailable(registryKey);
    }
    _processLeases[registryKey] = null;

    final resolvedDurability = durability ?? RestorePlatformDurability();
    final elapsed = Stopwatch()..start();
    RestoreLeaseLock? lock;
    var ownsProcessMarker = false;
    _ProcessOwnerProbe? processOwnerProbe;
    final instanceId = _newInstanceId();
    late final File processOwnerFile;
    try {
      await _ensureLeaseDirectory(
        appDataDirectory: appDataDirectory,
        leaseDirectory: leaseDirectory,
        durability: resolvedDurability,
      );
      processOwnerFile = File(
        p.join(leaseDirectory.path, '$_processOwnerPrefix$pid'),
      );
      // A predecessor engine in this process is retired before the lock is
      // taken. The record lock cannot see it: it is owned by this process, so
      // the predecessor's still-open descriptor never blocks this isolate.
      await _retireProcessPredecessor(
        ownerFile: processOwnerFile,
        registryKey: registryKey,
        grace: ownerGrace,
        elapsed: elapsed,
      );

      final initialLockType = await FileSystemEntity.type(
        lockFile.path,
        followLinks: false,
      );
      if (initialLockType == FileSystemEntityType.notFound) {
        await lockFile.create();
      } else if (initialLockType != FileSystemEntityType.file) {
        throw StateError('restore_business_lease_lock_file');
      }
      if (await FileSystemEntity.type(lockFile.path, followLinks: false) !=
          FileSystemEntityType.file) {
        throw StateError('restore_business_lease_lock_file');
      }
      await resolvedDurability.restrictFile(lockFile);
      lock = await _lockLeaseFile(
        lockFile: lockFile,
        registryKey: registryKey,
        grace: lockGrace,
      );

      // The marker is published only under the lock, so no other process can
      // mistake a live marker for a stale one while its owner is still racing
      // for the lock.
      processOwnerProbe = await _ProcessOwnerProbe.open(instanceId);
      await _claimProcessOwner(
        ownerFile: processOwnerFile,
        registryKey: registryKey,
        instanceId: instanceId,
        processOwnerProbe: processOwnerProbe,
        durability: resolvedDurability,
        grace: ownerGrace,
        elapsed: elapsed,
      );
      ownsProcessMarker = true;

      await _removeStaleProcessOwners(
        leaseDirectory: leaseDirectory,
        currentOwner: processOwnerFile,
      );

      final lease = RestoreBusinessLease._(
        lockFile: lockFile,
        instanceId: instanceId,
        processId: pid,
        processOwnerFile: processOwnerFile,
        processOwnerProbe: processOwnerProbe,
        registryKey: registryKey,
        lock: lock,
      );
      lock = null;
      _processLeases[registryKey] = lease;
      return lease;
    } catch (_) {
      await lock?.release();
      await processOwnerProbe?.close();
      if (ownsProcessMarker) {
        await _deleteProcessOwner(processOwnerFile);
      }
      _processLeases.remove(registryKey);
      rethrow;
    }
  }

  /// Takes the lease lock, waiting out a lock another process still holds.
  ///
  /// The wait uses its own window rather than the acquire-wide one, because a
  /// predecessor in this process and a dying previous process are independent
  /// delays that can both be in play on a cold start.
  static Future<RestoreLeaseLock> _lockLeaseFile({
    required File lockFile,
    required String registryKey,
    required Duration grace,
  }) async {
    final waited = Stopwatch()..start();
    while (true) {
      final lock = await RestoreLeaseLock.tryAcquire(lockFile);
      if (lock != null) return lock;
      if (waited.elapsed >= grace) {
        throw RestoreBusinessLeaseUnavailable(registryKey);
      }
      await Future<void>.delayed(_contentionPoll);
    }
  }

  /// Retires an owner marker left by an earlier engine in this same process.
  ///
  /// Throws [RestoreBusinessLeaseUnavailable] when the predecessor is still
  /// answering its probe once [grace] elapsed.
  static Future<void> _retireProcessPredecessor({
    required File ownerFile,
    required String registryKey,
    required Duration grace,
    required Stopwatch elapsed,
  }) async {
    final type = await FileSystemEntity.type(
      ownerFile.path,
      followLinks: false,
    );
    if (type == FileSystemEntityType.notFound) return;
    if (type != FileSystemEntityType.file) {
      throw StateError('restore_business_lease_process_owner');
    }
    if (await _awaitProcessOwnerRelease(
      ownerFile: ownerFile,
      grace: grace,
      elapsed: elapsed,
    )) {
      throw RestoreBusinessLeaseUnavailable(registryKey);
    }
    // The marker is named after this process, so no other process may own it,
    // and retiring it outside the lock cannot disturb another instance.
    await _deleteProcessOwner(ownerFile);
  }

  /// Waits for a same-process owner marker to stop answering its probe.
  ///
  /// Returns whether the previous owner still holds the lease once [grace]
  /// elapsed. Death is only accepted after [_ownerDeathConfirmations]
  /// consecutive silent probes, so a single stalled probe cannot retire a live
  /// owner.
  static Future<bool> _awaitProcessOwnerRelease({
    required File ownerFile,
    required Duration grace,
    required Stopwatch elapsed,
  }) async {
    var silentProbes = 0;
    while (true) {
      if (await _ProcessOwnerProbe.isLive(ownerFile)) {
        silentProbes = 0;
      } else if (++silentProbes >= _ownerDeathConfirmations) {
        return false;
      }
      if (elapsed.elapsed >= grace) return true;
      await Future<void>.delayed(_contentionPoll);
    }
  }

  /// Releases this lease. Repeated calls are harmless.
  Future<void> close() async {
    final lock = _lock;
    if (lock == null) return;
    _lock = null;

    Object? firstError;
    StackTrace? firstStackTrace;
    try {
      await lock.release();
    } catch (error, stackTrace) {
      firstError = error;
      firstStackTrace = stackTrace;
    }
    try {
      await _deleteProcessOwner(_processOwnerFile);
    } catch (error, stackTrace) {
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    }
    try {
      await _processOwnerProbe.close();
    } catch (error, stackTrace) {
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    } finally {
      if (identical(_processLeases[_registryKey], this)) {
        _processLeases.remove(_registryKey);
      }
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStackTrace!);
    }
  }

  static Future<void> _ensureLeaseDirectory({
    required Directory appDataDirectory,
    required Directory leaseDirectory,
    required RestoreDurability durability,
  }) async {
    final appDataType = await FileSystemEntity.type(
      appDataDirectory.path,
      followLinks: false,
    );
    if (appDataType == FileSystemEntityType.notFound) {
      await appDataDirectory.create(recursive: true);
    } else if (appDataType != FileSystemEntityType.directory) {
      throw StateError('restore_business_lease_app_data');
    }
    if (await FileSystemEntity.type(
          appDataDirectory.path,
          followLinks: false,
        ) !=
        FileSystemEntityType.directory) {
      throw StateError('restore_business_lease_app_data');
    }

    final leaseDirectoryType = await FileSystemEntity.type(
      leaseDirectory.path,
      followLinks: false,
    );
    if (leaseDirectoryType == FileSystemEntityType.notFound) {
      await leaseDirectory.create();
      await durability.restrictDirectory(leaseDirectory);
    } else if (leaseDirectoryType == FileSystemEntityType.directory) {
      await durability.restrictDirectory(leaseDirectory);
    } else {
      throw StateError('restore_business_lease_directory');
    }
    if (await FileSystemEntity.type(leaseDirectory.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw StateError('restore_business_lease_directory');
    }
  }

  static Future<void> _claimProcessOwner({
    required File ownerFile,
    required String registryKey,
    required String instanceId,
    required _ProcessOwnerProbe processOwnerProbe,
    required RestoreDurability durability,
    required Duration grace,
    required Stopwatch elapsed,
  }) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final type = await FileSystemEntity.type(
        ownerFile.path,
        followLinks: false,
      );
      if (type != FileSystemEntityType.notFound) {
        if (type == FileSystemEntityType.file) {
          if (await _awaitProcessOwnerRelease(
            ownerFile: ownerFile,
            grace: grace,
            elapsed: elapsed,
          )) {
            throw RestoreBusinessLeaseUnavailable(registryKey);
          }
          // The lease lock is already held here, so a marker that outlives its
          // isolate is the orphan left by hot restart or engine recreation and
          // every build mode may reclaim it.
          await _deleteProcessOwner(ownerFile);
        } else {
          throw StateError('restore_business_lease_process_owner');
        }
      }
      try {
        await ownerFile.create(exclusive: true);
      } on FileSystemException {
        final collidedType = await FileSystemEntity.type(
          ownerFile.path,
          followLinks: false,
        );
        if (collidedType == FileSystemEntityType.file) {
          throw RestoreBusinessLeaseUnavailable(registryKey);
        }
        if (collidedType != FileSystemEntityType.notFound) {
          throw StateError('restore_business_lease_process_owner');
        }
        if (attempt == 1) rethrow;
        continue;
      }
      try {
        if (await FileSystemEntity.type(ownerFile.path, followLinks: false) !=
            FileSystemEntityType.file) {
          throw StateError('restore_business_lease_process_owner');
        }
        await durability.restrictFile(ownerFile);
        final identity = jsonEncode({
          'instanceId': instanceId,
          'probePort': processOwnerProbe.port,
        });
        await ownerFile.writeAsString(identity);
        if (await FileSystemEntity.type(ownerFile.path, followLinks: false) !=
                FileSystemEntityType.file ||
            await ownerFile.readAsString() != identity) {
          throw StateError('restore_business_lease_process_owner_identity');
        }
        return;
      } catch (error, stackTrace) {
        try {
          await _deleteProcessOwner(ownerFile);
        } catch (_) {
          // Preserve the durability failure. A leftover marker is intentionally
          // fail-closed and will be cleaned by a later different process.
        }
        Error.throwWithStackTrace(error, stackTrace);
      }
    }
    throw StateError('restore_business_lease_process_owner');
  }

  static Future<void> _removeStaleProcessOwners({
    required Directory leaseDirectory,
    required File currentOwner,
  }) async {
    await for (final entity in leaseDirectory.list(followLinks: false)) {
      final name = p.basename(entity.path);
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      if (name == lockFileName) {
        if (type != FileSystemEntityType.file) {
          throw StateError('restore_business_lease_lock_file');
        }
        continue;
      }
      if (!RegExp(r'^owner_[0-9]+$').hasMatch(name) ||
          type != FileSystemEntityType.file) {
        throw StateError('restore_business_lease_directory_entry');
      }
      if (p.equals(entity.path, currentOwner.path)) continue;
      await File(entity.path).delete();
    }
    // Owner markers coordinate live isolates only. The OS file lock remains
    // authoritative across processes, so stale-marker cleanup needs no
    // post-crash durability barrier.
  }

  static Future<void> _deleteProcessOwner(File ownerFile) async {
    final type = await FileSystemEntity.type(
      ownerFile.path,
      followLinks: false,
    );
    if (type == FileSystemEntityType.notFound) return;
    if (type != FileSystemEntityType.file) {
      throw StateError('restore_business_lease_process_owner');
    }
    await ownerFile.delete();
  }

  static String _newInstanceId() {
    final random = Random.secure();
    return List<int>.generate(
      16,
      (_) => random.nextInt(256),
    ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }
}

final class _ProcessOwnerProbe {
  _ProcessOwnerProbe._(this._server, this._token);

  static const _timeout = Duration(milliseconds: 300);

  final ServerSocket _server;
  final String _token;

  int get port => _server.port;

  static Future<_ProcessOwnerProbe> open(String token) async {
    final server = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
      shared: false,
    );
    final probe = _ProcessOwnerProbe._(server, token);
    server.listen(probe._answer, onError: (_) {});
    return probe;
  }

  static Future<bool> isLive(File ownerFile) async {
    try {
      final decoded = jsonDecode(await ownerFile.readAsString());
      if (decoded is! Map<String, dynamic>) return false;
      final token = decoded['instanceId'];
      final port = decoded['probePort'];
      if (token is! String || port is! int || port <= 0 || port > 65535) {
        return false;
      }
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: _timeout,
      );
      try {
        socket.writeln(token);
        await socket.flush();
        final response = await socket
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .first
            .timeout(_timeout);
        return response == 'alive';
      } finally {
        socket.destroy();
      }
    } catch (_) {
      return false;
    }
  }

  Future<void> _answer(Socket socket) async {
    try {
      final request = await socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(_timeout);
      socket.writeln(request == _token ? 'alive' : 'denied');
      await socket.flush();
    } catch (_) {
      // A malformed probe is not a lease failure.
    } finally {
      await socket.close();
    }
  }

  Future<void> close() => _server.close();
}
