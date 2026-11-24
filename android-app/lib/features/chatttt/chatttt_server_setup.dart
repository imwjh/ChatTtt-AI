import 'package:flutter/material.dart';

import '../../core/chatttt/chatttt_config.dart';
import '../../core/chatttt/chatttt_service.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/snackbar.dart';

/// ChatTtt 首次启动引导：填写服务地址。
///
/// 填完立刻保存并连接，之后也可以在「设置 → 服务地址」里修改。
Future<void> showChatTttServerSetupDialog(BuildContext context) async {
  final l10n = AppLocalizations.of(context)!;
  final controller = TextEditingController(
    text: ChatTttConfig.instance.serverUrl ?? '',
  );
  final result = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.chattttServerDialogTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: l10n.chattttSettingsServiceAddress,
              hintText: 'https://example.com',
            ),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.chattttServerDialogBody,
            style: const TextStyle(fontSize: 12, height: 1.5),
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(controller.text.trim()),
          child: Text(l10n.chattttServerConnect),
        ),
      ],
    ),
  );
  controller.dispose();
  if (result == null || result.isEmpty) return;

  await ChatTttConfig.instance.setServerUrl(result);
  final url = ChatTttConfig.instance.serverUrl;
  if (url == null || url.isEmpty) return;

  var reachable = false;
  try {
    await ChatTttService.instance.ensureConnected(url);
    reachable = true;
  } catch (_) {
    reachable = false;
  }
  if (!context.mounted) return;
  showAppSnackBar(
    context,
    message: reachable
        ? l10n.chattttServerAddressUpdated
        : l10n.chattttServerAddressFailed,
    type: reachable ? NotificationType.success : NotificationType.warning,
  );
}
