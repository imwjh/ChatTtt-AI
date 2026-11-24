import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_back_button.dart';
import '../../../shared/widgets/ios_settings_rows.dart';
import '../../../shared/widgets/section_card.dart';
import '../../../theme/app_semantic_colors.dart';
import 'about_page.dart';
import 'data_management_page.dart';
import 'help_feedback_page.dart';
import 'minor_mode_page.dart';
import 'notifications_page.dart';
import 'privacy_page.dart';
import 'quota_page.dart';
import 'service_terms_page.dart';

/// 设置页。
///
/// 按账户、外观、支持、数据与隐私、关于分组，服务地址移至关于页。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsProvider>();
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text(l10n.settingsPageTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          IosSectionHeader(
            text: l10n.chattttSettingsAccountSection,
            first: true,
          ),
          SectionCard(
            children: [
              IosNavRow(
                icon: Icons.speed_outlined,
                label: l10n.chattttQuotaLabel,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const QuotaPage()),
                ),
              ),
              const IosRowDivider(),
              IosNavRow(
                icon: Icons.notifications_none_rounded,
                label: l10n.chattttNotificationsLabel,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const NotificationsPage(),
                  ),
                ),
              ),
            ],
          ),
          IosSectionHeader(text: l10n.chattttSettingsAppearanceSection),
          SectionCard(
            children: [
              IosNavRow(
                icon: Icons.contrast_outlined,
                label: l10n.displaySettingsPageThemeSettingsTitle,
                detailText: _themeLabel(settings.themeMode, l10n),
                onTap: () => _pickTheme(context, settings, l10n),
              ),
            ],
          ),
          IosSectionHeader(text: l10n.chattttSettingsSupportSection),
          SectionCard(
            children: [
              IosNavRow(
                icon: Icons.help_outline,
                label: l10n.chattttHelpFeedback,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const HelpFeedbackPage(),
                  ),
                ),
              ),
              const IosRowDivider(),
              IosNavRow(
                icon: Icons.shield_outlined,
                label: l10n.chattttMinorMode,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const MinorModePage(),
                  ),
                ),
              ),
              const IosRowDivider(),
              IosNavRow(
                icon: Icons.system_update_alt_rounded,
                label: l10n.chattttCheckUpdate,
                detailText: '2.3.0',
                onTap: _checkForUpdates,
              ),
            ],
          ),
          IosSectionHeader(text: l10n.chattttSettingsDataSection),
          SectionCard(
            children: [
              IosNavRow(
                icon: Icons.privacy_tip_outlined,
                label: l10n.chattttPrivacySettings,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const PrivacyPage()),
                ),
              ),
              const IosRowDivider(),
              IosNavRow(
                icon: Icons.storage_outlined,
                label: l10n.chattttDataManagement,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const DataManagementPage(),
                  ),
                ),
              ),
            ],
          ),
          IosSectionHeader(text: l10n.settingsPageAbout),
          SectionCard(
            children: [
              IosNavRow(
                icon: Icons.info_outline,
                label: 'ChatTtt',
                subtitle: '2.3.0',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const AboutPage()),
                ),
              ),
              const IosRowDivider(),
              IosNavRow(
                icon: Icons.description_outlined,
                label: l10n.chattttTermsOfService,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ServiceTermsPage(),
                  ),
                ),
              ),
            ],
          ),
          IosSectionFooter(text: l10n.chattttSettingsFooter),
        ],
      ),
    );
  }

  Future<void> _checkForUpdates() async {
    final l10n = AppLocalizations.of(context)!;
    final navigator = Navigator.of(context, rootNavigator: true);
    unawaited(
      _showUpdateDialog(
        builder: (_) => const _UpdateLoadingCard(),
        barrierLabel: l10n.chattttCheckUpdateChecking,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    if (!mounted) return;
    navigator.pop();
    await _showUpdateDialog(
      builder: (_) => const _UpdateResultCard(),
      barrierLabel: l10n.chattttCheckUpdateLatestTitle,
    );
  }

  /// 检查更新弹窗统一使用淡入 + 缩放动画，卡片本身即超椭圆方形。
  Future<void> _showUpdateDialog({
    required WidgetBuilder builder,
    required String barrierLabel,
    bool barrierDismissible = false,
  }) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierColor: Colors.black.withValues(alpha: 0.32),
      barrierLabel: barrierLabel,
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (dialogContext, _, _) => Material(
        type: MaterialType.transparency,
        child: builder(dialogContext),
      ),
      transitionBuilder: (dialogContext, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.86, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  static String _themeLabel(ThemeMode mode, AppLocalizations l10n) {
    switch (mode) {
      case ThemeMode.light:
        return l10n.settingsPageLightMode;
      case ThemeMode.dark:
        return l10n.settingsPageDarkMode;
      case ThemeMode.system:
        return l10n.settingsPageSystemMode;
    }
  }

  Future<void> _pickTheme(
    BuildContext context,
    SettingsProvider settings,
    AppLocalizations l10n,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final mode in const <ThemeMode>[
                ThemeMode.system,
                ThemeMode.light,
                ThemeMode.dark,
              ])
                IosNavRow(
                  icon: switch (mode) {
                    ThemeMode.system => Icons.brightness_auto_outlined,
                    ThemeMode.light => Icons.light_mode_outlined,
                    ThemeMode.dark => Icons.dark_mode_outlined,
                  },
                  label: _themeLabel(mode, l10n),
                  trailing: settings.themeMode == mode
                      ? const Icon(Icons.check, size: 18)
                      : const SizedBox.shrink(),
                  onTap: () {
                    settings.setThemeMode(mode);
                    Navigator.of(sheetContext).pop();
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

/// 检查更新加载卡：正方形超椭圆面板，只放进度和文案。
class _UpdateLoadingCard extends StatelessWidget {
  const _UpdateLoadingCard();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Container(
        width: 150,
        height: 150,
        decoration: BoxDecoration(
          color: context.overlaySurface,
          borderRadius: BorderRadius.circular(38),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.18),
            width: 0.8,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 30,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              l10n.chattttCheckUpdateChecking,
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurface.withValues(alpha: 0.65),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 检查更新结果卡：与加载卡同样的圆角面板与弹出动画。
class _UpdateResultCard extends StatelessWidget {
  const _UpdateResultCard();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Container(
        width: 300,
        padding: const EdgeInsets.fromLTRB(24, 26, 24, 20),
        decoration: BoxDecoration(
          color: context.overlaySurface,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.18),
            width: 0.8,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 30,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: cs.onSurface.withValues(alpha: 0.06),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check_rounded, size: 24, color: cs.onSurface),
            ),
            const SizedBox(height: 14),
            Text(
              l10n.chattttCheckUpdateLatestTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.chattttCheckUpdateLatestBody,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: cs.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.chattttCheckUpdateDone),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
