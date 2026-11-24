import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_back_button.dart';
import '../../../shared/widgets/ios_settings_rows.dart';
import '../../../shared/widgets/section_card.dart';
import '../../../shared/widgets/snackbar.dart';

/// 数据管理页（演示用：删除操作为本地假流程）。
class DataManagementPage extends StatefulWidget {
  const DataManagementPage({super.key});

  @override
  State<DataManagementPage> createState() => _DataManagementPageState();
}

class _DataManagementPageState extends State<DataManagementPage> {
  bool _busy = false;

  Future<void> _confirmDelete({required bool local}) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          local
              ? l10n.chattttDataLocalConfirmTitle
              : l10n.chattttDataCloudConfirmTitle,
        ),
        content: Text(
          local
              ? l10n.chattttDataLocalConfirmBody
              : l10n.chattttDataCloudConfirmBody,
          style: const TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.chattttDataCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.chattttDataDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    await Future<void>.delayed(const Duration(milliseconds: 1000));
    if (!mounted) return;
    setState(() => _busy = false);
    showAppSnackBar(
      context,
      message: local
          ? l10n.chattttDataDeletedLocal
          : l10n.chattttDataDeletedCloud,
      type: NotificationType.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text(l10n.chattttDataPageTitle),
      ),
      body: Column(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: _busy
                ? const Padding(
                    key: ValueKey('busy'),
                    padding: EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.all(Radius.circular(999)),
                      child: LinearProgressIndicator(minHeight: 3),
                    ),
                  )
                : const SizedBox(key: ValueKey('idle'), height: 0),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                IosSectionHeader(
                  text: l10n.chattttDataSectionLocal,
                  first: true,
                ),
                SectionCard(
                  children: [
                    IosNavRow(
                      icon: Icons.smartphone_outlined,
                      label: l10n.chattttDataLocalTitle,
                      subtitle: l10n.chattttDataLocalSubtitle,
                      destructive: true,
                      subtitleMaxLines: 2,
                      trailing: Text(
                        l10n.chattttDataDelete,
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onTap: _busy ? null : () => _confirmDelete(local: true),
                    ),
                  ],
                ),
                IosSectionHeader(text: l10n.chattttDataSectionCloud),
                SectionCard(
                  children: [
                    IosNavRow(
                      icon: Icons.cloud_outlined,
                      label: l10n.chattttDataCloudTitle,
                      subtitle: l10n.chattttDataCloudSubtitle,
                      destructive: true,
                      subtitleMaxLines: 2,
                      trailing: Text(
                        l10n.chattttDataDelete,
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onTap: _busy ? null : () => _confirmDelete(local: false),
                    ),
                  ],
                ),
                IosSectionFooter(text: l10n.chattttDataFooter),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
