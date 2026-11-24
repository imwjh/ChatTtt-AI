import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_back_button.dart';
import '../../../shared/widgets/ios_settings_rows.dart';
import '../../../shared/widgets/section_card.dart';

/// 通知偏好页（仅本地保存）。
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  static const _repliesKey = 'chatttt_notify_replies_v1';
  static const _soundKey = 'chatttt_notify_sound_v1';
  static const _vibrationKey = 'chatttt_notify_vibration_v1';
  static const _dndKey = 'chatttt_notify_dnd_v1';

  bool _replies = true;
  bool _sound = true;
  bool _vibration = true;
  bool _dnd = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _replies = prefs.getBool(_repliesKey) ?? true;
        _sound = prefs.getBool(_soundKey) ?? true;
        _vibration = prefs.getBool(_vibrationKey) ?? true;
        _dnd = prefs.getBool(_dndKey) ?? true;
      });
    } catch (_) {}
  }

  Future<void> _save(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text(l10n.chattttNotificationsPageTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          SectionCard(
            children: [
              IosSwitchRow(
                icon: Icons.notifications_none_rounded,
                label: l10n.chattttNotificationsReplies,
                subtitle: l10n.chattttNotificationsRepliesSubtitle,
                value: _replies,
                onChanged: (value) {
                  setState(() => _replies = value);
                  _save(_repliesKey, value);
                },
              ),
              const IosRowDivider(),
              IosSwitchRow(
                icon: Icons.volume_up_outlined,
                label: l10n.chattttNotificationsSound,
                value: _sound,
                onChanged: (value) {
                  setState(() => _sound = value);
                  _save(_soundKey, value);
                },
              ),
              const IosRowDivider(),
              IosSwitchRow(
                icon: Icons.vibration_rounded,
                label: l10n.chattttNotificationsVibration,
                value: _vibration,
                onChanged: (value) {
                  setState(() => _vibration = value);
                  _save(_vibrationKey, value);
                },
              ),
              const IosRowDivider(),
              IosSwitchRow(
                icon: Icons.nights_stay_outlined,
                label: l10n.chattttNotificationsDnd,
                subtitle: l10n.chattttNotificationsDndSubtitle,
                value: _dnd,
                onChanged: (value) {
                  setState(() => _dnd = value);
                  _save(_dndKey, value);
                },
              ),
            ],
          ),
          IosSectionFooter(text: l10n.chattttNotificationsHint),
        ],
      ),
    );
  }
}
