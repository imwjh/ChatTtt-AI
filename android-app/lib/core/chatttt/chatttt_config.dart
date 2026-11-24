import 'package:shared_preferences/shared_preferences.dart';

/// ChatTtt 演示用"模型"列表。
///
/// 与网页端 `web/src/App.tsx` 的 MODELS 完全一致：三个模型全部由后台真人扮演，
/// 选择器只负责让界面看起来像正经的 AI 客户端。
class ChatTttModel {
  const ChatTttModel({
    required this.id,
    required this.name,
    required this.description,
  });

  final String id;
  final String name;
  final String description;
}

const List<ChatTttModel> kChatTttModels = <ChatTttModel>[
  ChatTttModel(
    id: 'little-sunbee-5.3',
    name: 'Little Sunbee 5.3',
    description: '轻量模型',
  ),
  ChatTttModel(
    id: 'super-sunbee-5.5',
    name: 'Super Sunbee 5.5',
    description: '顶级最强大脑',
  ),
  ChatTttModel(
    id: 'fuck-image-2.1',
    name: 'Fuck‑Image 2.1',
    description: '图像识别与生图模型',
  ),
];

/// ChatTtt 的运行时配置。
///
/// 服务器地址不写死：
/// 1. 应用内保存的地址（设置页可改）；
/// 2. 打包时 `--dart-define=CHATTTT_SERVER_URL=...` 注入的地址；
/// 3. 都没有时保持为空，由首次启动引导页收集。
class ChatTttConfig {
  ChatTttConfig._(this._prefs);

  final SharedPreferences _prefs;

  static const String _kServerUrl = 'chatttt.server_url';
  static const String _kModelId = 'chatttt.model_id';
  static const String _kVisitorId = 'chatttt.visitor_id';
  static const String _kLastSeenAt = 'chatttt.last_seen_at';

  /// 内置供应商在 Kelivo 供应商体系里的 key。
  static const String providerKey = 'chatttt';

  /// 打包期注入的服务器地址。
  static const String buildTimeServerUrl = String.fromEnvironment(
    'CHATTTT_SERVER_URL',
  );

  static ChatTttConfig? _instance;

  /// 已加载的实例；必须在 [load] 之后使用。
  static ChatTttConfig get instance {
    final instance = _instance;
    if (instance == null) {
      throw StateError('ChatTttConfig.load() 尚未调用');
    }
    return instance;
  }

  static Future<ChatTttConfig> load() async {
    if (_instance != null) return _instance!;
    final prefs = await SharedPreferences.getInstance();
    final config = ChatTttConfig._(prefs);
    final saved = prefs.getString(_kServerUrl);
    if ((saved == null || saved.isEmpty) && buildTimeServerUrl.isNotEmpty) {
      await config.setServerUrl(buildTimeServerUrl);
    }
    _instance = config;
    return config;
  }

  /// 当前生效的服务器地址；为空表示尚未配置。
  String? get serverUrl {
    final saved = _prefs.getString(_kServerUrl);
    if (saved != null && saved.isNotEmpty) return saved;
    if (buildTimeServerUrl.isNotEmpty) {
      return normalizeServerUrl(buildTimeServerUrl);
    }
    return null;
  }

  bool get isConfigured => (serverUrl ?? '').isNotEmpty;

  Future<void> setServerUrl(String raw) async {
    await _prefs.setString(_kServerUrl, normalizeServerUrl(raw));
  }

  /// 当前选中的演示模型 id。
  String get modelId {
    final saved = _prefs.getString(_kModelId);
    if (saved != null && kChatTttModels.any((m) => m.id == saved)) {
      return saved;
    }
    return kChatTttModels.first.id;
  }

  Future<void> setModelId(String id) async {
    await _prefs.setString(_kModelId, id);
  }

  /// 最后一条已交付给界面的后台消息时间（毫秒），用于重连 / 冷启动补收。
  int get lastSeenMessageAt => _prefs.getInt(_kLastSeenAt) ?? 0;

  Future<void> setLastSeenMessageAt(int value) async {
    await _prefs.setInt(_kLastSeenAt, value);
  }

  /// 访客身份：与服务端约定的 sessionId，持久化后同一台设备始终是同一位访客。
  String get visitorId {
    var saved = _prefs.getString(_kVisitorId);
    if (saved == null || saved.isEmpty) {
      saved = 'v-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
      _prefs.setString(_kVisitorId, saved);
    }
    return saved;
  }

  /// 把用户输入的地址规整成可直接用于 Socket.io 的 base url。
  static String normalizeServerUrl(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return '';
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      value = 'https://$value';
    }
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }
}
