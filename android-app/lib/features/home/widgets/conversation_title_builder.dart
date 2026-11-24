import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../../core/services/chat/chat_service.dart';
import '../../../l10n/app_localizations.dart';

class ConversationTitleBuilder extends StatelessWidget {
  const ConversationTitleBuilder({
    super.key,
    required this.conversationId,
    required this.isTemporary,
    required this.builder,
  });

  final String? conversationId;
  final bool isTemporary;
  final Widget Function(BuildContext context, String title) builder;

  static String _clip(String text, {int max = 40}) {
    final runes = text.runes.toList(growable: false);
    if (runes.length <= max) return text;
    return '${String.fromCharCodes(runes.take(max))}…';
  }

  @override
  Widget build(BuildContext context) {
    // Selecting null replaces the previous chat's title subscription.
    final id = isTemporary ? null : conversationId;
    final info = context
        .select<ChatService, ({String? title, String? lastUser})>((chat) {
          if (id == null) return (title: null, lastUser: null);
          return (
            title: chat.getConversation(id)?.title,
            lastUser: chat.latestUserMessageText(id),
          );
        });
    final l10n = AppLocalizations.of(context)!;
    if (isTemporary) return builder(context, l10n.temporaryChatTitle);
    // ChatTtt：顶部标题显示最近一条用户发给后台的消息。
    final lastUser = info.lastUser?.trim();
    if (lastUser != null && lastUser.isNotEmpty) {
      return builder(context, _clip(lastUser));
    }
    final title = info.title;
    return builder(
      context,
      title == null || title.trim().isEmpty ? l10n.titleForLocale : title,
    );
  }
}
