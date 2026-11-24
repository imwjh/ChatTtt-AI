import 'package:flutter/material.dart';

import '../../icons/lucide_adapter.dart';
import '../../l10n/app_localizations.dart';

/// 统一的二级/三级页面返回按钮（与关于页一致）。
class AppBackButton extends StatefulWidget {
  const AppBackButton({super.key});

  @override
  State<AppBackButton> createState() => _AppBackButtonState();
}

class _AppBackButtonState extends State<AppBackButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final color = cs.onSurface;
    return Tooltip(
      message: l10n.settingsPageBackButton,
      child: Semantics(
        button: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: () => Navigator.of(context).maybePop(),
          child: AnimatedScale(
            scale: _pressed ? 0.95 : 1.0,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Icon(
                Lucide.ArrowLeft,
                size: 22,
                color: _pressed ? color.withValues(alpha: 0.7) : color,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
