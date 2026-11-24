import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../../core/models/assistant.dart';
import '../../../shared/widgets/chatttt_mark.dart';
import '../../../shared/widgets/emoji_text.dart';
import '../../../shared/widgets/avatar_image.dart';

class AssistantAvatar extends StatelessWidget {
  const AssistantAvatar({
    super.key,
    required this.assistant,
    this.fallbackName,
    this.size = 28,
  });

  final Assistant? assistant;
  final String? fallbackName;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final avatarValue = assistant?.avatar?.trim() ?? '';

    // 未配置头像时使用 ChatTtt 自有 AI 标记，不再用姓名首字母填充。
    if (avatarValue.isEmpty) return ChatTttMark(size: size);

    Widget avatar;
    if (avatarValue.startsWith('http') ||
        (!kIsWeb &&
            (avatarValue.startsWith('/') || avatarValue.contains(':')))) {
      avatar = AvatarImage(
        source: avatarValue,
        isNetwork: avatarValue.startsWith('http'),
        size: size,
        fallback: ChatTttMark(size: size),
      );
    } else {
      avatar = _AssistantEmojiAvatar(cs: cs, emoji: avatarValue, size: size);
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: cs.onSurface.withValues(alpha: isDark ? 0.24 : 0.12),
          width: 0.5,
        ),
      ),
      child: avatar,
    );
  }
}

class _AssistantEmojiAvatar extends StatelessWidget {
  const _AssistantEmojiAvatar({
    required this.cs,
    required this.emoji,
    required this.size,
  });

  final ColorScheme cs;
  final String emoji;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: EmojiText(
        emoji.characters.take(1).toString(),
        fontSize: size * 0.5,
        optimizeEmojiAlign: true,
      ),
    );
  }
}
