/// Rotates API keys for search services that configure multiple keys.
///
/// The rotation pool is `[primary, ...extras]` (trimmed, deduplicated).
/// The next-index cursor is kept in memory per service id, matching the
/// ephemeral round-robin behavior of `ApiKeyManager` for model providers.
class SearchApiKeyRotator {
  SearchApiKeyRotator._();

  static final SearchApiKeyRotator instance = SearchApiKeyRotator._();

  final Map<String, int> _indices = {}; // serviceId -> next pool index

  /// Picks the key to use for the next request of [serviceId].
  ///
  /// When the cleaned pool holds a single key (e.g. an empty [primary] with
  /// one extra), that key is returned without advancing any cursor. When the
  /// pool is empty the raw [primary] is returned as-is.
  String select(String serviceId, String primary, List<String> extras) {
    final pool = _pool(primary, extras);
    if (pool.isEmpty) return primary;
    if (pool.length == 1) return pool.first;
    final current = _indices[serviceId] ?? 0;
    final index = current % pool.length;
    _indices[serviceId] = (index + 1) % pool.length;
    return pool[index];
  }

  /// All keys that participate in rotation, in rotation order.
  static List<String> rotationPool(String primary, List<String> extras) =>
      _pool(primary, extras);

  /// Splits a batch paste into individual keys. Accepts keys separated by
  /// newlines, commas, semicolons, or whitespace; trims and deduplicates
  /// while preserving order.
  static List<String> parseBatch(String input) {
    final seen = <String>{};
    final keys = <String>[];
    for (final part in input.split(RegExp(r'[\s,;]+'))) {
      final key = part.trim();
      if (key.isEmpty || !seen.add(key)) continue;
      keys.add(key);
    }
    return keys;
  }

  /// Masks a key for display, keeping the first and last four characters.
  static String mask(String key) {
    final trimmed = key.trim();
    if (trimmed.length <= 8) return '••••••••';
    return '${trimmed.substring(0, 4)}••••${trimmed.substring(trimmed.length - 4)}';
  }

  static List<String> _pool(String primary, List<String> extras) {
    final seen = <String>{};
    final pool = <String>[];
    void add(String key) {
      final trimmed = key.trim();
      if (trimmed.isEmpty || !seen.add(trimmed)) return;
      pool.add(trimmed);
    }

    add(primary);
    for (final key in extras) {
      add(key);
    }
    return pool;
  }
}
