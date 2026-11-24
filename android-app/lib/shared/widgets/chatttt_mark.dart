import 'dart:math' as math;

import 'package:flutter/material.dart';

/// ChatTtt 的 AI 标记。
///
/// 黑白灰几何星芒，不使用字母或外链图片，任意尺寸都保持清晰。
/// [inverted] 为 true 时是"实心方块 + 反色星芒"，适合头像与模型图标。
class ChatTttMark extends StatelessWidget {
  const ChatTttMark({
    super.key,
    this.size = 28,
    this.inverted = true,
    this.foreground,
    this.background,
  });

  final double size;
  final bool inverted;
  final Color? foreground;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg =
        background ??
        (inverted
            ? (isDark ? const Color(0xFFFFFFFF) : const Color(0xFF000000))
            : Colors.transparent);
    final fg =
        foreground ??
        (inverted
            ? (isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF))
            : Theme.of(context).colorScheme.onSurface);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _ChatTttMarkPainter(background: bg, foreground: fg),
      ),
    );
  }
}

class _ChatTttMarkPainter extends CustomPainter {
  const _ChatTttMarkPainter({
    required this.background,
    required this.foreground,
  });

  final Color background;
  final Color foreground;

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    if (side <= 0) return;
    final rect = Rect.fromLTWH(
      (size.width - side) / 2,
      (size.height - side) / 2,
      side,
      side,
    );
    if (background.a > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(side * 0.3)),
        Paint()..color = background,
      );
    }

    final center = Offset(rect.left + side * 0.46, rect.top + side * 0.54);
    _sparkle(canvas, center, side * 0.29);
    _sparkle(
      canvas,
      Offset(rect.left + side * 0.74, rect.top + side * 0.27),
      side * 0.105,
    );
  }

  /// 四角内凹的星芒：控制点拉向中心，形成干脆的负空间。
  void _sparkle(Canvas canvas, Offset c, double r) {
    final shoulder = r * 0.18;
    final path = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx + shoulder, c.dy - shoulder, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx + shoulder, c.dy + shoulder, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx - shoulder, c.dy + shoulder, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx - shoulder, c.dy - shoulder, c.dx, c.dy - r)
      ..close();
    canvas.drawPath(path, Paint()..color = foreground);
  }

  @override
  bool shouldRepaint(_ChatTttMarkPainter old) =>
      old.background != background || old.foreground != foreground;
}
