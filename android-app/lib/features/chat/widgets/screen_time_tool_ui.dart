import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_font_weights.dart';

/// Parsed result of the `get_screen_time` local tool.
class ScreenTimeResult {
  const ScreenTimeResult({
    required this.totalMinutes,
    required this.apps,
    this.start,
    this.end,
    this.error,
  });

  final int totalMinutes;
  final List<ScreenTimeAppUsage> apps;
  final String? start;
  final String? end;
  final String? error;

  bool get isNoPermission => error == 'NO_PERMISSION';
  bool get hasApps => apps.isNotEmpty;

  static ScreenTimeResult? tryParse(String? content) {
    if (content == null || content.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(content);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      final error = map['error']?.toString();
      final appsRaw = map['apps'];
      final apps = <ScreenTimeAppUsage>[];
      if (appsRaw is List) {
        for (final item in appsRaw) {
          if (item is! Map) continue;
          final appMap = Map<String, dynamic>.from(item);
          final name = (appMap['app_name'] ?? appMap['package'] ?? '')
              .toString()
              .trim();
          if (name.isEmpty) continue;
          final totalMs = _asInt(appMap['total_ms']);
          final totalMinutes =
              _asInt(appMap['total_minutes']) ??
              (totalMs != null ? totalMs ~/ 60000 : 0);
          apps.add(
            ScreenTimeAppUsage(
              name: name,
              totalMs: totalMs ?? (totalMinutes * 60000),
              totalMinutes: totalMinutes,
            ),
          );
        }
      }
      return ScreenTimeResult(
        totalMinutes: _asInt(map['total_minutes']) ?? 0,
        apps: apps,
        start: map['start']?.toString(),
        end: map['end']?.toString(),
        error: error,
      );
    } catch (_) {
      return null;
    }
  }
}

class ScreenTimeAppUsage {
  const ScreenTimeAppUsage({
    required this.name,
    required this.totalMs,
    required this.totalMinutes,
  });

  final String name;
  final int totalMs;
  final int totalMinutes;
}

/// Compact summary for the tool card / chain-of-thought step.
class ScreenTimeToolSummary extends StatelessWidget {
  const ScreenTimeToolSummary({
    super.key,
    required this.result,
    this.maxApps = 3,
    this.textColor,
    this.secondaryColor,
    this.errorColor,
  });

  final ScreenTimeResult result;
  final int maxApps;
  final Color? textColor;
  final Color? secondaryColor;
  final Color? errorColor;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final primary = textColor ?? cs.onPrimaryContainer;
    final secondary = secondaryColor ?? primary.withValues(alpha: 0.8);
    final err = errorColor ?? cs.error;

    if (result.isNoPermission) {
      return Text(
        l10n.chatMessageWidgetScreenTimePermissionRequired,
        style: TextStyle(fontSize: 12, height: 1.35, color: err),
      );
    }
    if (!result.hasApps) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.chatMessageWidgetScreenTimeTotal,
                style: TextStyle(fontSize: 12, height: 1.3, color: secondary),
              ),
            ),
            Text(
              formatScreenTimeMinutes(result.totalMinutes),
              style: TextStyle(
                fontSize: 12,
                height: 1.3,
                fontWeight: AppFontWeights.medium,
                color: primary,
              ),
            ),
          ],
        ),
        ...result.apps.take(maxApps).map((app) {
          return Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    app.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, height: 1.3, color: primary),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  formatScreenTimeMinutes(app.totalMinutes),
                  style: TextStyle(fontSize: 12, height: 1.3, color: secondary),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

/// Full detail body for the screen-time tool result sheet/dialog.
class ScreenTimeToolDetailBody extends StatelessWidget {
  const ScreenTimeToolDetailBody({
    super.key,
    required this.result,
    this.scrollController,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 24),
  });

  final ScreenTimeResult result;
  final ScrollController? scrollController;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final maxAppMs = result.apps
        .map((a) => a.totalMs)
        .fold<int>(0, (prev, v) => v > prev ? v : prev)
        .clamp(1, 1 << 62);

    final rangeLabel = () {
      final start = result.start;
      final end = result.end;
      if (start == null || end == null) return null;
      return '${formatScreenTimeRange(start)} → ${formatScreenTimeRange(end)}';
    }();

    return ListView(
      controller: scrollController,
      padding: padding,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.chatMessageWidgetScreenTimeTotal,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: AppFontWeights.semibold,
                  color: cs.onSurface,
                ),
              ),
            ),
            Text(
              formatScreenTimeMinutes(result.totalMinutes),
              style: TextStyle(
                fontSize: 16,
                fontWeight: AppFontWeights.semibold,
                color: cs.primary,
              ),
            ),
          ],
        ),
        if (rangeLabel != null) ...[
          const SizedBox(height: 4),
          Text(
            rangeLabel,
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
        const SizedBox(height: 16),
        ...result.apps.map((app) {
          final progress = (app.totalMs / maxAppMs).clamp(0.0, 1.0);
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        app.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14, color: cs.onSurface),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      formatScreenTimeMinutes(app.totalMinutes),
                      style: TextStyle(
                        fontSize: 14,
                        color: cs.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: cs.onSurface.withValues(alpha: 0.08),
                    color: cs.primary,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

String formatScreenTimeMinutes(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h > 0 && m > 0) return '${h}h ${m}m';
  if (h > 0) return '${h}h';
  return '${m}m';
}

/// Formats an ISO-ish timestamp to `MM-dd HH:mm`, falling back to the raw value.
String formatScreenTimeRange(String iso) {
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) return iso;
  final local = parsed.toLocal();
  final mm = local.month.toString().padLeft(2, '0');
  final dd = local.day.toString().padLeft(2, '0');
  final hh = local.hour.toString().padLeft(2, '0');
  final min = local.minute.toString().padLeft(2, '0');
  return '$mm-$dd $hh:$min';
}

int? _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}
