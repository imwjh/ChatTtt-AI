import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_back_button.dart';
import '../../../shared/widgets/ios_settings_rows.dart';
import '../../../shared/widgets/section_card.dart';

/// 隐私设置页（仅本地保存）。
class PrivacyPage extends StatefulWidget {
  const PrivacyPage({super.key});

  @override
  State<PrivacyPage> createState() => _PrivacyPageState();
}

class _PrivacyPageState extends State<PrivacyPage> {
  static const _trainingKey = 'chatttt_privacy_training_v1';
  static const _marketingKey = 'chatttt_privacy_marketing_v1';
  static const _analyticsKey = 'chatttt_privacy_analytics_v1';
  static const _personalizationKey = 'chatttt_privacy_personalization_v1';

  bool _training = false;
  bool _marketing = false;
  bool _analytics = true;
  bool _personalization = true;

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
        _training = prefs.getBool(_trainingKey) ?? false;
        _marketing = prefs.getBool(_marketingKey) ?? false;
        _analytics = prefs.getBool(_analyticsKey) ?? true;
        _personalization = prefs.getBool(_personalizationKey) ?? true;
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
        title: Text(l10n.chattttPrivacyPageTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          IosSectionHeader(
            text: l10n.chattttPrivacySectionExperience,
            first: true,
          ),
          SectionCard(
            children: [
              IosSwitchRow(
                icon: Icons.auto_awesome_outlined,
                label: l10n.chattttPrivacyTrainingTitle,
                subtitle: l10n.chattttPrivacyTrainingSubtitle,
                value: _training,
                onChanged: (value) {
                  setState(() => _training = value);
                  _save(_trainingKey, value);
                },
              ),
              const IosRowDivider(),
              IosSwitchRow(
                icon: Icons.mail_outline,
                label: l10n.chattttPrivacyMarketingTitle,
                subtitle: l10n.chattttPrivacyMarketingSubtitle,
                value: _marketing,
                onChanged: (value) {
                  setState(() => _marketing = value);
                  _save(_marketingKey, value);
                },
              ),
              const IosRowDivider(),
              IosSwitchRow(
                icon: Icons.analytics_outlined,
                label: l10n.chattttPrivacyAnalyticsTitle,
                subtitle: l10n.chattttPrivacyAnalyticsSubtitle,
                value: _analytics,
                onChanged: (value) {
                  setState(() => _analytics = value);
                  _save(_analyticsKey, value);
                },
              ),
              const IosRowDivider(),
              IosSwitchRow(
                icon: Icons.tune,
                label: l10n.chattttPrivacyPersonalizationTitle,
                subtitle: l10n.chattttPrivacyPersonalizationSubtitle,
                value: _personalization,
                onChanged: (value) {
                  setState(() => _personalization = value);
                  _save(_personalizationKey, value);
                },
              ),
            ],
          ),
          IosSectionFooter(text: l10n.chattttPrivacyFooter),
        ],
      ),
    );
  }
}
