import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:Kelivo/core/chatttt/chatttt_config.dart';
import 'package:Kelivo/core/chatttt/chatttt_service.dart';
import 'package:Kelivo/core/services/api/stream/stream_chunk.dart';
import 'package:Kelivo/core/utils/multimodal_input_utils.dart';
import 'package:Kelivo/utils/sandbox_path_resolver.dart';

/// ChatTtt 的"模型供应商"。
///
/// 它不对接任何 LLM HTTP 接口，而是直接连 ChatTtt 的 Socket.io 服务：
/// 访客发消息 → 后台真人扮演的 AI 回复 → 逐字渲染。
/// 事件名与负载结构与网页端完全一致，手机与网页可以同时在线。
class ChatTttProvider {
  const ChatTttProvider._();

  static const ChatTttImageCodec _codec = ChatTttImageCodec();

  /// 发送一轮对话并产出流式 chunk。
  static Stream<StreamChunk> sendMessageStream({
    required List<Map<String, dynamic>> messages,
    List<String>? userImagePaths,
    required String modelId,
    bool Function()? isCancelled,
  }) async* {
    final service = ChatTttService.instance;
    final serverUrl = ChatTttConfig.instance.serverUrl;
    if (serverUrl == null || serverUrl.isEmpty) {
      throw const ChatTttServiceError('not-configured');
    }
    await service.ensureConnected(serverUrl);

    final text = _extractUserText(messages);
    final audios = await _prepareAudio(messages);
    final images = await _prepareImages(userImagePaths);

    // 先挂上等待者再发送：服务端的 visitor:error（后台离线）可能在
    // 发送后立刻到达，顺序反了就会丢错误并一直卡在等待回复。
    service.clearUnclaimedError();
    final waiter = service.waitForReply();
    try {
      // 语音与图片在后端都是独立消息（与网页端一致）：先语音，再图片，最后文本。
      for (final audio in audios) {
        service.sendAudio(
          key: audio.key,
          dataUri: audio.dataUri,
          durationSeconds: audio.durationSeconds,
        );
      }
      for (final image in images) {
        service.sendImage(key: image.key, dataUri: image.dataUri);
      }
      if (text != null && text.isNotEmpty) {
        service.sendText(text);
      }
    } catch (_) {
      waiter.cancel();
      rethrow;
    }

    // 等待回复期间轮询取消状态：用户点停止时立刻摘除等待者，
    // 否则这一轮的 waiter 会吞掉后台下一条回复。
    late ChatTttServerMessage reply;
    while (true) {
      if (isCancelled?.call() ?? false) {
        waiter.cancel();
        return;
      }
      try {
        reply = await waiter.future.timeout(const Duration(milliseconds: 120));
        break;
      } on TimeoutException {
        continue;
      }
    }
    waiter.cancel();

    final id = 'chatttt-${reply.id ?? reply.at}';
    switch (reply.type) {
      case 'image':
        yield* _imageStream(id: id, reply: reply);
      case 'audio':
        yield* _audioStream(id: id, reply: reply);
      default:
        yield* _textStream(id: id, reply: reply, isCancelled: isCancelled);
    }

    yield Finish(finishReason: 'stop', model: modelId);
  }

  /// 文本回复：逐字输出，节奏与网页端一致（12–32ms/字）。
  static Stream<StreamChunk> _textStream({
    required String id,
    required ChatTttServerMessage reply,
    bool Function()? isCancelled,
  }) async* {
    final full = reply.text ?? '';
    yield TextStart(id);
    final random = Random();
    for (final rune in full.runes) {
      if (isCancelled?.call() ?? false) return;
      // TextDelta 是增量片段，不能重复发送累计全文。
      yield TextDelta(id: id, text: String.fromCharCode(rune));
      await Future<void>.delayed(
        Duration(milliseconds: 12 + random.nextInt(21)),
      );
    }
    yield TextEnd(id);
  }

  /// 图片回复：dataURI 直接作为图片 part。
  static Stream<StreamChunk> _imageStream({
    required String id,
    required ChatTttServerMessage reply,
  }) async* {
    final dataUri = reply.imageData;
    if (dataUri == null || dataUri.isEmpty) return;
    final mime = mimeOfDataUri(dataUri);
    yield ImageStart(id: id, mimeType: mime);
    yield ImageSnapshot(id: id, data: dataUri);
    yield ImageEnd(id);
  }

  /// 语音回复：落盘后作为文件 part（Kelivo 会用内置播放器渲染）。
  static Stream<StreamChunk> _audioStream({
    required String id,
    required ChatTttServerMessage reply,
  }) async* {
    final dataUri = reply.audioData;
    if (dataUri == null || dataUri.isEmpty) return;
    final mime = mimeOfDataUri(dataUri);
    final bytes = dataUriToBytes(dataUri);
    final key = reply.audioKey ?? ChatTttMediaStore.makeKey('aud');
    final extension = extensionForMime(mime, fallback: 'm4a');
    final path = await ChatTttMediaStore.instance.saveBytes(
      key: key,
      bytes: bytes,
      extension: extension,
    );
    // 文件名必须沿用 voice_<秒>s_ 约定，聊天页才会渲染成语音胶囊并显示时长。
    final seconds = (reply.duration ?? 0).round().clamp(0, 3600);
    yield GeneratedFile(
      uri: path,
      name: 'voice_${seconds}s_$key.$extension',
      mime: mime,
    );
  }

  /// 从请求里取出用户文本（OpenAI 风格的 content 可能是字符串或分片数组）。
  static String? _extractUserText(List<Map<String, dynamic>> messages) {
    for (final message in messages.reversed) {
      if (message['role'] != 'user') continue;
      // 只看最新一条用户消息。图片/语音消息没有文本时必须返回 null，
      // 不能回退到更早的文本，否则每发一张图都会把上一段文字重发一遍。
      final content = message['content'];
      if (content is String) {
        final trimmed = content.trim();
        return trimmed.isEmpty ? null : trimmed;
      }
      if (content is List) {
        final buffer = StringBuffer();
        for (final part in content) {
          if (part is Map && part['type'] == 'text') {
            buffer.write(part['text'] ?? '');
          }
        }
        final trimmed = buffer.toString().trim();
        return trimmed.isEmpty ? null : trimmed;
      }
      return null;
    }
    return null;
  }

  /// 读取最近一条用户消息里的语音附件，转成 dataURI。
  ///
  /// 与网页端一致：音频单独一条 `audio` 消息发送，时长随消息附给后台。
  static Future<List<_PreparedAudio>> _prepareAudio(
    List<Map<String, dynamic>> messages,
  ) async {
    final refs = <InternalMediaRef>[];
    for (final message in messages.reversed) {
      if (message['role'] != 'user') continue;
      final parsed = parseInternalMediaRefs(
        message[multimodalInternalMediaPathsKey],
      );
      for (final ref in parsed) {
        final mime = (ref.mime ?? '').toLowerCase();
        if (mime.startsWith('audio/')) refs.add(ref);
      }
      break;
    }
    final prepared = <_PreparedAudio>[];
    for (final ref in refs) {
      try {
        final fixedPath = SandboxPathResolver.fix(ref.uri);
        final file = File(fixedPath);
        if (!await file.exists()) continue;
        final length = await file.length();
        if (length <= 0 || length > 8 * 1024 * 1024) continue;
        final raw = await file.readAsBytes();
        final mime = (ref.mime ?? '').isNotEmpty
            ? ref.mime!
            : _audioMimeFromPath(fixedPath);
        prepared.add(
          _PreparedAudio(
            key: ChatTttMediaStore.makeKey('aud'),
            dataUri: bytesToDataUri(raw, mime),
            durationSeconds: _audioDurationFromPath(fixedPath),
          ),
        );
      } catch (_) {
        // 单个语音失败不影响整条消息
      }
    }
    return prepared;
  }

  static String _audioMimeFromPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.wav')) return 'audio/wav';
    if (lower.endsWith('.webm')) return 'audio/webm';
    return 'audio/mp4';
  }

  static int _audioDurationFromPath(String path) {
    final match = RegExp(r'voice_(\d+)s_').firstMatch(path);
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }

  /// 读取用户选择的图片，压缩后转成 dataURI。
  static Future<List<_PreparedImage>> _prepareImages(
    List<String>? userImagePaths,
  ) async {
    final paths = userImagePaths;
    if (paths == null || paths.isEmpty) return const <_PreparedImage>[];
    final prepared = <_PreparedImage>[];
    for (final rawPath in paths) {
      try {
        final path = SandboxPathResolver.fix(rawPath.trim());
        if (path.isEmpty) continue;
        if (path.startsWith('data:image/')) {
          prepared.add(
            _PreparedImage(
              key: ChatTttMediaStore.makeKey('img'),
              dataUri: path,
            ),
          );
          continue;
        }
        final mime = inferMediaMimeFromSource(path, fallbackMime: '');
        if (mime.isNotEmpty && !isImageMime(mime)) continue;
        final file = File(path);
        if (!await file.exists()) continue;
        final raw = await file.readAsBytes();
        final compressed = _codec.compress(raw);
        prepared.add(
          _PreparedImage(
            key: ChatTttMediaStore.makeKey('img'),
            dataUri: bytesToDataUri(compressed.bytes, compressed.mime),
          ),
        );
      } catch (_) {
        // 单张图片失败不影响整条消息
      }
    }
    return prepared;
  }
}

class _PreparedImage {
  const _PreparedImage({required this.key, required this.dataUri});

  final String key;
  final String dataUri;
}

class _PreparedAudio {
  const _PreparedAudio({
    required this.key,
    required this.dataUri,
    required this.durationSeconds,
  });

  final String key;
  final String dataUri;
  final int durationSeconds;
}

/// 供上层复用的字节类型别名（避免到处 import dart:typed_data）。
typedef ChatTttBytes = Uint8List;
