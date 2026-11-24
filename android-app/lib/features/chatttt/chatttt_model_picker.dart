import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/chatttt/chatttt_config.dart';
import '../../core/providers/settings_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/chatttt_mark.dart';
import '../../shared/widgets/ios_settings_rows.dart';

/// ChatTtt 的模型选择面板。
///
/// 与设置页的主题选择器保持同一套样式：底部弹层 + 原生导航行 + 选中勾选，
/// 不再使用自定义卡片，保证全局 UI 语言一致。
Future<void> showChatTttModelPicker(
  BuildContext context, {
  String? currentModelId,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final settings = context.read<SettingsProvider>();
  final current =
      currentModelId ??
      settings.currentModelId ??
      ChatTttConfig.instance.modelId;

  final selected = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => _ChatTttModelSheet(
      selectedId: current,
      title: l10n.chattttModelPickerTitle,
    ),
  );
  if (selected == null || selected == current) return;

  await settings.setCurrentModel(ChatTttConfig.providerKey, selected);
  await ChatTttConfig.instance.setModelId(selected);
}

class _ChatTttModelSheet extends StatelessWidget {
  const _ChatTttModelSheet({required this.selectedId, required this.title});

  final String selectedId;
  final String title;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.1,
                  color: cs.onSurface,
                ),
              ),
            ),
          ),
          for (final model in kChatTttModels)
            IosNavRow(
              leading: ChatTttMark(size: 30),
              label: model.name,
              subtitle: model.description,
              subtitleMaxLines: 2,
              trailing: model.id == selectedId
                  ? const Icon(Icons.check, size: 18)
                  : const SizedBox.shrink(),
              onTap: () => Navigator.of(context).pop(model.id),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
