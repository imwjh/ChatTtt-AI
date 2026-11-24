import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 仅供展示的本地免费额度统计。
///
/// 只统计用户实际发送的文字字符数，按自然日记录，按月重置；
/// 图片、语音和非文字内容不计入。数据只保存在本机。
class UsageQuotaService extends ChangeNotifier {
  UsageQuotaService._();

  static final UsageQuotaService instance = UsageQuotaService._();

  static const int monthlyQuota = 5000000;
  static const String _prefsKey = 'chatttt_usage_quota_v1';

  final Map<String, int> _daily = <String, int>{};
  String _month = '';
  Future<void>? _loading;

  bool get isLoaded => _month.isNotEmpty;

  int get used => _daily.values.fold(0, (sum, value) => sum + value);

  int get remaining => (monthlyQuota - used).clamp(0, monthlyQuota);

  double get progress => (used / monthlyQuota).clamp(0.0, 1.0);

  int get todayCount => _daily[_dayKey(DateTime.now())] ?? 0;

  String get monthLabel {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  Future<void> ensureLoaded() {
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final storedMonth = decoded['month'];
          if (storedMonth is String) _month = storedMonth;
          final days = decoded['days'];
          if (days is Map) {
            for (final entry in days.entries) {
              final key = entry.key;
              final value = entry.value;
              if (key is String && value is num) {
                _daily[key] = value.toInt();
              }
            }
          }
        }
      }
    } catch (_) {}
    _resetIfNeeded();
    _prune();
    notifyListeners();
  }

  Future<void> recordText(String text) async {
    await ensureLoaded();
    final count = text.trim().runes.length;
    if (count <= 0) return;
    _resetIfNeeded();
    final key = _dayKey(DateTime.now());
    _daily[key] = (_daily[key] ?? 0) + count;
    _prune();
    notifyListeners();
    await _persist();
  }

  List<({DateTime day, int count})> lastDays(int days) {
    final now = DateTime.now();
    final out = <({DateTime day, int count})>[];
    for (var offset = days - 1; offset >= 0; offset--) {
      final day = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: offset));
      out.add((day: day, count: _daily[_dayKey(day)] ?? 0));
    }
    return out;
  }

  void _resetIfNeeded() {
    final current = monthLabel;
    if (_month == current) return;
    _month = current;
    _daily.clear();
    unawaited(_persist());
  }

  void _prune() {
    if (_daily.length <= 120) return;
    final keys = _daily.keys.toList()..sort((a, b) => a.compareTo(b));
    for (final key in keys.take(_daily.length - 90)) {
      _daily.remove(key);
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode(<String, dynamic>{'month': _month, 'days': _daily}),
      );
    } catch (_) {}
  }

  static String _dayKey(DateTime day) {
    final month = day.month.toString().padLeft(2, '0');
    final date = day.day.toString().padLeft(2, '0');
    return '${day.year}-$month-$date';
  }
}
