import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import 'chatttt_config.dart';

/// 后端下发的消息（与 `server/server.js` 的结构一致）。
class ChatTttServerMessage {
  const ChatTttServerMessage({
    this.id,
    required this.from,
    required this.type,
    this.text,
    this.imageUrl,
    this.imageKey,
    this.imageData,
    this.audioKey,
    this.audioData,
    this.duration,
    required this.at,
  });

  final String? id;
  final String from;
  final String type;
  final String? text;
  final String? imageUrl;
  final String? imageKey;
  final String? imageData;
  final String? audioKey;
  final String? audioData;
  final double? duration;
  final int at;

  bool get isFromUser => from == 'user';

  factory ChatTttServerMessage.fromJson(Map<String, dynamic> json) {
    double? duration;
    final raw = json['duration'];
    if (raw is num) {
      duration = raw.toDouble();
    } else if (raw is String) {
      duration = double.tryParse(raw);
    }
    return ChatTttServerMessage(
      id: json['id'] as String?,
      from: json['from'] as String? ?? 'user',
      type: json['type'] as String? ?? 'text',
      text: json['text'] as String?,
      imageUrl: json['imageUrl'] as String?,
      imageKey: json['imageKey'] as String?,
      imageData: json['imageData'] as String?,
      audioKey: json['audioKey'] as String?,
      audioData: json['audioData'] as String?,
      duration: duration,
      at:
          (json['at'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
    );
  }
}

/// 可取消的回复等待句柄。
///
/// 用户停止生成 / 流被取消时，调用 [cancel] 把等待者从队列中摘除，
/// 避免后台下一条回复被一个已经没人监听的 waiter 吃掉。
class ChatTttReplyWaiter {
  final Completer<ChatTttServerMessage> _completer =
      Completer<ChatTttServerMessage>();
  bool _cancelled = false;
  final int startedAt = DateTime.now().millisecondsSinceEpoch;

  Future<ChatTttServerMessage> get future => _completer.future;

  bool get isActive => !_cancelled && !_completer.isCompleted;

  void complete(ChatTttServerMessage message) {
    if (isActive) _completer.complete(message);
  }

  void completeError(Object error) {
    if (isActive) _completer.completeError(error);
  }

  void cancel() {
    _cancelled = true;
  }
}

/// 后台不可用等错误。
class ChatTttServiceError implements Exception {
  const ChatTttServiceError(this.code);

  final String code;

  /// 后台没有真人在线 —— 与网页端显示同款错误。
  bool get isAdminOffline => code == 'admin-offline';

  @override
  String toString() => 'ChatTttServiceError($code)';
}

/// ChatTtt 与后台的实时通道。
///
/// 协议与网页端（`web/src/App.tsx` + `server/server.js`）完全一致：
/// - `visitor:join` / `visitor:message` / `visitor:typing` 发给服务端
/// - `visitor:joined` / `visitor:new-message` / `visitor:error` / `visitor:typing` 来自服务端
///
/// 媒体本体以 dataURI 随消息附带，服务端只在内存中转，双方各自把本体存本地。
class ChatTttService {
  ChatTttService._();

  static ChatTttService? _instance;

  static ChatTttService get instance {
    return _instance ??= ChatTttService._();
  }

  io.Socket? _socket;
  String? _baseUrl;
  Completer<void>? _connectWaiter;
  Completer<void>? _joinWaiter;

  /// 已收到但还没有等待者认领的错误（后台离线等）。
  ChatTttServiceError? _unclaimedError;

  /// 没有对应请求的助手消息（后台主动发来 / 上一轮请求结束后才到）。
  final StreamController<ChatTttServerMessage> _unpromptedController =
      StreamController<ChatTttServerMessage>.broadcast();

  /// 已交付的时间水位（持久化），用于冷启动 / 重连后补收后台回复。
  int _lastSeenAt = 0;

  /// 已交付消息 id（按到达顺序，最多保留 512 条），防止重放造成重复气泡。
  final LinkedHashSet<String> _seenMessageIds = LinkedHashSet<String>();

  final StreamController<ChatTttServerMessage> _messageController =
      StreamController<ChatTttServerMessage>.broadcast();
  final StreamController<ChatTttServiceError> _errorController =
      StreamController<ChatTttServiceError>.broadcast();
  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();

  /// 等待回复的请求队列：后台的回复按到达顺序依次交付给最早的请求。
  final List<ChatTttReplyWaiter> _pending = <ChatTttReplyWaiter>[];

  Stream<ChatTttServerMessage> get messages => _messageController.stream;

  /// 后台主动发来、没有对应请求的助手消息。
  Stream<ChatTttServerMessage> get unpromptedMessages =>
      _unpromptedController.stream;

  Stream<ChatTttServiceError> get errors => _errorController.stream;

  /// 连接状态变化（true = 已连接）。
  Stream<bool> get connection => _connectionController.stream;

  bool get isConnected => _socket?.connected ?? false;

  /// 建立连接（幂等）。地址变化时会断开旧连接重连。
  ///
  /// 只负责发起连接，不等待握手完成；需要确认可用时用 [ensureConnected]。
  Future<void> connect(String baseUrl) async {
    final existing = _socket;
    if (_baseUrl == baseUrl && existing != null) {
      // 复用同一个地址上已有的连接 / 正在进行的重连，避免每次发送都重建 socket。
      if (!existing.connected) {
        if (_connectWaiter == null || _connectWaiter!.isCompleted) {
          _connectWaiter = Completer<void>();
        }
        if (_joinWaiter == null || _joinWaiter!.isCompleted) {
          _joinWaiter = Completer<void>();
        }
        existing.connect();
      }
      return;
    }
    _baseUrl = baseUrl;
    _teardown();
    _unclaimedError = null;
    _connectWaiter = Completer<void>();
    _joinWaiter = Completer<void>();
    _seenMessageIds.clear();
    _lastSeenAt = ChatTttConfig.instance.lastSeenMessageAt;

    final socket = io.io(
      baseUrl,
      io.OptionBuilder()
          .enableForceNew()
          .enableReconnection()
          // 3.1.x 的 polling 传输在 Android 上会静默失败，只保留 websocket。
          .setTransports(<String>['websocket'])
          .setReconnectionDelay(1200)
          .setReconnectionAttempts(9999)
          .setTimeout(20000)
          .build(),
    );
    _socket = socket;

    socket.onConnect((_) {
      final waiter = _connectWaiter;
      if (waiter != null && !waiter.isCompleted) waiter.complete();
      if (_joinWaiter == null || _joinWaiter!.isCompleted) {
        _joinWaiter = Completer<void>();
      }
      _emitConnection(true);
      socket.emit('visitor:join', <String, dynamic>{
        'sessionId': ChatTttConfig.instance.visitorId,
      });
    });

    socket.onDisconnect((_) {
      if (_connectWaiter == null || _connectWaiter!.isCompleted) {
        _connectWaiter = Completer<void>();
      }
      if (_joinWaiter == null || _joinWaiter!.isCompleted) {
        _joinWaiter = Completer<void>();
      }
      _emitConnection(false);
    });

    socket.onConnectError((_) {
      _emitConnection(false);
    });

    socket.on('visitor:new-message', (dynamic payload) {
      if (payload is! Map) return;
      final raw = payload['message'];
      if (raw is! Map) return;
      final message = ChatTttServerMessage.fromJson(
        Map<String, dynamic>.from(raw),
      );
      if (!_acceptMessage(message)) return;
      _messageController.add(message);
      _deliverAssistantMessage(message);
    });

    // 重连 / 冷启动后补收断线期间后台已经发出的回复，避免消息永久丢失。
    socket.on('visitor:joined', (dynamic payload) {
      if (payload is! Map) return;
      final raw = payload['messages'];
      final list = raw is List ? raw : const <dynamic>[];
      final missed = <ChatTttServerMessage>[];
      for (final item in list) {
        if (item is! Map) continue;
        final message = ChatTttServerMessage.fromJson(
          Map<String, dynamic>.from(item),
        );
        if (message.isFromUser) continue;
        if (message.at <= _lastSeenAt) continue;
        if (!_acceptMessage(message)) continue;
        missed.add(message);
      }
      missed.sort((a, b) => a.at.compareTo(b.at));
      for (final message in missed) {
        _messageController.add(message);
        // 断线期间收到的回复如果晚于本轮请求开始时间，就交给本轮 waiter；
        // 更早的历史消息只作为未配对消息追加，不能冒充本轮的答案。
        final waiter = _takeWaiterFor(message.at);
        if (waiter != null) {
          waiter.complete(message);
        } else {
          _emitUnprompted(message);
        }
      }
      final join = _joinWaiter;
      if (join != null && !join.isCompleted) join.complete();
    });

    socket.on('visitor:error', (dynamic payload) {
      final code = payload is Map ? payload['code'] as String? : null;
      final error = ChatTttServiceError(code ?? 'unknown');
      _errorController.add(error);
      // 后台无人在线：把错误交给最早等待的请求；暂时没有等待者时留到下一次。
      final waiter = _takeWaiter();
      if (waiter != null) {
        waiter.completeError(error);
      } else {
        _unclaimedError = error;
      }
    });

    socket.connect();
  }

  /// 确认已经连上后台，未连上时最多等待 [timeout]。
  ///
  /// 发送消息前调用：连接失败时抛出 `unreachable`，不会再静默地
  /// 拿着一个未连接的 socket 去发消息。
  Future<void> ensureConnected(
    String baseUrl, {
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (_baseUrl != baseUrl || !isConnected) {
      unawaited(connect(baseUrl));
    }
    if (isConnected) return;
    final waiter = _connectWaiter;
    if (waiter == null) {
      throw const ChatTttServiceError('unreachable');
    }
    try {
      await waiter.future.timeout(timeout);
    } on TimeoutException {
      throw const ChatTttServiceError('unreachable');
    }
    // 等访客加入完成再发消息，确保服务端历史补收先于本轮请求落地。
    final join = _joinWaiter;
    if (join != null) {
      try {
        await join.future.timeout(const Duration(seconds: 3));
      } on TimeoutException {
        // 老版本服务端没有 visitor:joined 时仍然允许发送。
      }
    }
  }

  /// 记录消息 id 与时间水位；返回 false 表示这条消息已经交付过。
  ///
  /// 只对助手消息做去重与水位推进，用户自己的消息不参与补收。
  bool _acceptMessage(ChatTttServerMessage message) {
    final id = message.id;
    if (id != null && id.isNotEmpty) {
      if (_seenMessageIds.contains(id)) return false;
      _seenMessageIds.add(id);
      while (_seenMessageIds.length > 512) {
        _seenMessageIds.remove(_seenMessageIds.first);
      }
    }
    if (message.at > _lastSeenAt) {
      _lastSeenAt = message.at;
      unawaited(ChatTttConfig.instance.setLastSeenMessageAt(_lastSeenAt));
    }
    return true;
  }

  /// 取出最早的仍在等待的 waiter，顺带清掉已取消 / 已完成的条目。
  ChatTttReplyWaiter? _takeWaiter() {
    while (_pending.isNotEmpty) {
      final waiter = _pending.removeAt(0);
      if (waiter.isActive) return waiter;
    }
    return null;
  }

  /// 只在消息时间不早于 waiter 开始时间时才交付，避免历史消息冒充新回复。
  ChatTttReplyWaiter? _takeWaiterFor(int messageAt) {
    while (_pending.isNotEmpty && !_pending.first.isActive) {
      _pending.removeAt(0);
    }
    if (_pending.isEmpty) return null;
    final waiter = _pending.first;
    if (messageAt < waiter.startedAt) return null;
    _pending.removeAt(0);
    return waiter;
  }

  void _deliverAssistantMessage(ChatTttServerMessage message) {
    if (message.isFromUser) return;
    final waiter = _takeWaiter();
    if (waiter != null) {
      waiter.complete(message);
      return;
    }
    _emitUnprompted(message);
  }

  void _emitUnprompted(ChatTttServerMessage message) {
    if (!_unpromptedController.isClosed) {
      _unpromptedController.add(message);
    }
  }

  void _emitConnection(bool value) {
    if (!_connectionController.isClosed) {
      _connectionController.add(value);
    }
  }

  void _teardown() {
    cancelPending();
    final socket = _socket;
    _socket = null;
    _connectWaiter = null;
    _joinWaiter = null;
    _unclaimedError = null;
    if (socket == null) return;
    socket.offAny();
    socket.destroy();
    socket.dispose();
  }

  /// 发送文本（不等待回复）。
  void sendText(String text) {
    final socket = _socket;
    if (socket == null || !socket.connected) {
      throw const ChatTttServiceError('disconnected');
    }
    _unclaimedError = null;
    socket.emit('visitor:message', <String, dynamic>{
      'type': 'text',
      'text': text,
    });
  }

  /// 发送图片（不等待回复）。
  void sendImage({required String key, required String dataUri}) {
    final socket = _socket;
    if (socket == null || !socket.connected) {
      throw const ChatTttServiceError('disconnected');
    }
    _unclaimedError = null;
    socket.emit('visitor:message', <String, dynamic>{
      'type': 'image',
      'imageKey': key,
      'imageData': dataUri,
    });
  }

  /// 发送语音消息（不等待回复）。
  void sendAudio({
    required String key,
    required String dataUri,
    required int durationSeconds,
  }) {
    final socket = _socket;
    if (socket == null || !socket.connected) {
      throw const ChatTttServiceError('disconnected');
    }
    _unclaimedError = null;
    socket.emit('visitor:message', <String, dynamic>{
      'type': 'audio',
      'audioKey': key,
      'audioData': dataUri,
      'duration': durationSeconds,
    });
  }

  /// 清理上一次请求遗留的错误（一条带图消息会让服务端逐条回错误）。
  void clearUnclaimedError() {
    _unclaimedError = null;
  }

  /// 等待后台的下一条回复。
  ///
  /// 队列按到达顺序分发：后台的回复依次交给最早发起的等待者。
  /// 返回的句柄可 [ChatTttReplyWaiter.cancel]，取消后不会再吞掉后台回复。
  ChatTttReplyWaiter waitForReply() {
    final waiter = ChatTttReplyWaiter();
    final unclaimed = _unclaimedError;
    if (unclaimed != null) {
      _unclaimedError = null;
      waiter.completeError(unclaimed);
      return waiter;
    }
    _pending.add(waiter);
    return waiter;
  }

  /// 通知后台"正在输入"。
  void sendTyping() {
    final socket = _socket;
    if (socket == null || !socket.connected) return;
    socket.emit('visitor:typing', <String, dynamic>{});
  }

  /// 取消全部等待（兜底；单个请求请用 waiter.cancel）。
  void cancelPending() {
    while (_pending.isNotEmpty) {
      _pending.removeAt(0).cancel();
    }
  }

  void dispose() {
    _teardown();
    _messageController.close();
    _errorController.close();
    _connectionController.close();
    _unpromptedController.close();
  }
}

/// 媒体文件的本地存储（对应网页端的 IndexedDB）。
class ChatTttMediaStore {
  ChatTttMediaStore._();

  static ChatTttMediaStore? _instance;

  static ChatTttMediaStore get instance => _instance ??= ChatTttMediaStore._();

  Directory? _dir;

  Future<Directory> _directory() async {
    final cached = _dir;
    if (cached != null) return cached;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}${Platform.pathSeparator}chatttt');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _dir = dir;
    return dir;
  }

  /// 按 key 保存媒体本体，返回本地绝对路径。
  Future<String> saveBytes({
    required String key,
    required Uint8List bytes,
    required String extension,
  }) async {
    final dir = await _directory();
    final file = File('${dir.path}${Platform.pathSeparator}$key.$extension');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// 生成媒体 key（发送方生成，接收方沿用同一个 key）。
  static String makeKey(String prefix) {
    final now = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final rand = List<int>.generate(6, (_) => DateTime.now().microsecond % 36);
    final suffix = rand.map((b) => b.toRadixString(36)).join();
    return '$prefix-$now-$suffix';
  }
}

/// 图片压缩：与网页端同一套参数（最长边 1600px、WebP、目标 ≤280KB）。
///
/// 纯 Dart 实现，直接在当前 isolate 跑（图片本身已被前端压缩过）。
class ChatTttImageCodec {
  const ChatTttImageCodec({this.maxBytes = 280 * 1024, this.maxEdge = 1600});

  final int maxBytes;
  final int maxEdge;

  ({Uint8List bytes, String mime}) compress(
    Uint8List bytes, {
    String fallbackMime = 'image/jpeg',
  }) {
    img.Image? decoded;
    try {
      decoded = img.decodeImage(bytes);
    } catch (_) {
      decoded = null;
    }
    if (decoded == null) return (bytes: bytes, mime: fallbackMime);

    final longest = decoded.width > decoded.height
        ? decoded.width
        : decoded.height;
    var target = decoded;
    if (longest > maxEdge) {
      final scale = maxEdge / longest;
      target = img.copyResize(
        decoded,
        width: (decoded.width * scale).round().clamp(1, maxEdge),
        height: (decoded.height * scale).round().clamp(1, maxEdge),
        interpolation: img.Interpolation.average,
      );
    }

    const qualities = <int>[85, 72, 60, 47, 35];
    Uint8List? best;
    for (final q in qualities) {
      try {
        // image 包默认是无损 WebP，quality 会被忽略体积反而更大；
        // 必须显式 lossless: false 才能得到真正压缩后的 WebP。
        final encoded = img.encodeWebP(
          target,
          lossless: false,
          quality: q,
          method: 4,
        );
        if (encoded.isEmpty) continue;
        best = encoded;
        if (encoded.length <= maxBytes) {
          return (bytes: encoded, mime: 'image/webp');
        }
      } catch (_) {
        // 继续尝试更低质量；全部失败时用下面的兜底。
      }
    }
    if (best != null) return (bytes: best, mime: 'image/webp');
    // WebP 编码不可用时退回 JPEG，至少保证图片能送达。
    try {
      final jpeg = img.encodeJpg(target, quality: 80);
      if (jpeg.isNotEmpty) return (bytes: jpeg, mime: 'image/jpeg');
    } catch (_) {}
    return (bytes: bytes, mime: fallbackMime);
  }
}

/// 字节数组 → dataURI（与网页端 `blobToDataUri` 等价）。
String bytesToDataUri(Uint8List bytes, String mime) {
  return 'data:$mime;base64,${base64Encode(bytes)}';
}

/// dataURI → 字节数组。
Uint8List dataUriToBytes(String dataUri) {
  final comma = dataUri.indexOf(',');
  if (comma < 0) return Uint8List(0);
  return base64Decode(dataUri.substring(comma + 1));
}

/// 从 dataURI 取 MIME 类型。
String mimeOfDataUri(String dataUri) {
  final comma = dataUri.indexOf(',');
  if (comma < 0) return 'application/octet-stream';
  final meta = dataUri.substring(0, comma);
  final match = RegExp(r'data:([^;]+)', caseSensitive: false).firstMatch(meta);
  return match?.group(1)?.toLowerCase() ?? 'application/octet-stream';
}

/// MIME → 文件扩展名。
String extensionForMime(String mime, {required String fallback}) {
  switch (mime) {
    case 'image/webp':
      return 'webp';
    case 'image/jpeg':
      return 'jpg';
    case 'image/png':
      return 'png';
    case 'audio/mp4':
    case 'audio/m4a':
      return 'm4a';
    case 'audio/webm':
      return 'webm';
    case 'audio/ogg':
      return 'ogg';
    case 'audio/mpeg':
      return 'mp3';
    default:
      return fallback;
  }
}
