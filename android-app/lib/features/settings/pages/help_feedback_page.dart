import 'package:flutter/material.dart';

import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_back_button.dart';

/// 帮助与反馈页：演示用的加载失败状态。
class HelpFeedbackPage extends StatefulWidget {
  const HelpFeedbackPage({super.key});

  @override
  State<HelpFeedbackPage> createState() => _HelpFeedbackPageState();
}

class _HelpFeedbackPageState extends State<HelpFeedbackPage> {
  bool _loading = false;

  Future<void> _retry() async {
    if (_loading) return;
    setState(() => _loading = true);
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text(l10n.chattttHelpFeedback),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.96, end: 1).animate(animation),
                child: child,
              ),
            ),
            child: _loading
                ? const SizedBox(
                    key: ValueKey('loading'),
                    width: 30,
                    height: 30,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  )
                : Column(
                    key: const ValueKey('error'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          color: cs.onSurface.withValues(alpha: 0.06),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Lucide.TriangleAlert,
                          size: 34,
                          color: cs.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        l10n.chattttHelpErrorTitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.chattttHelpErrorBody,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.5,
                          color: cs.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: _retry,
                        icon: const Icon(Lucide.RotateCw, size: 17),
                        label: Text(l10n.chattttHelpRetry),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
