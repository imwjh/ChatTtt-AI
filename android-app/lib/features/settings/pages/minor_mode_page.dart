import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_back_button.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../theme/app_font_weights.dart';
import '../../../theme/app_semantic_colors.dart';

/// 未成年人模式（前端展示与本地状态）。
class MinorModePage extends StatefulWidget {
  const MinorModePage({super.key});

  @override
  State<MinorModePage> createState() => _MinorModePageState();
}

class _MinorModePageState extends State<MinorModePage> {
  static const _enabledKey = 'chatttt_minor_mode_enabled_v1';
  static const _pinKey = 'chatttt_minor_mode_pin_v1';

  bool _enabled = false;
  String _pin = '';
  bool _loaded = false;

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
        _enabled = prefs.getBool(_enabledKey) ?? false;
        _pin = prefs.getString(_pinKey) ?? '';
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _persist({required bool enabled, String? pin}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledKey, enabled);
      if (pin != null) await prefs.setString(_pinKey, pin);
      if (!enabled) await prefs.remove(_pinKey);
    } catch (_) {}
  }

  Future<void> _handleAction() async {
    final l10n = AppLocalizations.of(context)!;
    if (!_enabled) {
      final pin = await _showPinSheet(
        title: l10n.chattttMinorModeSetPin,
        confirmLabel: l10n.chattttMinorModeConfirm,
      );
      if (pin == null || pin.length != 4 || !mounted) return;
      setState(() {
        _enabled = true;
        _pin = pin;
      });
      await _persist(enabled: true, pin: pin);
      if (mounted) {
        showAppSnackBar(
          context,
          message: l10n.chattttMinorModeEnabledToast,
          type: NotificationType.success,
        );
      }
      return;
    }
    final entered = await _showPinSheet(
      title: l10n.chattttMinorModeEnterPin,
      confirmLabel: l10n.chattttMinorModeConfirm,
      errorText: l10n.chattttMinorModePinError,
      verify: (value) => value == _pin,
    );
    if (entered == null || !mounted) return;
    setState(() => _enabled = false);
    await _persist(enabled: false);
    if (mounted) {
      showAppSnackBar(
        context,
        message: l10n.chattttMinorModeDisabledToast,
        type: NotificationType.success,
      );
    }
  }

  Future<String?> _showPinSheet({
    required String title,
    required String confirmLabel,
    String? errorText,
    bool Function(String value)? verify,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    String? error;
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: context.overlaySurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            MediaQuery.viewInsetsOf(sheetContext).bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: AppFontWeights.semibold,
                  letterSpacing: -0.2,
                  color: Theme.of(sheetContext).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: true,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 4,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  letterSpacing: 12,
                  fontWeight: AppFontWeights.semibold,
                ),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: l10n.chattttMinorModePinHint,
                  errorText: error,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 50,
                child: FilledButton(
                  onPressed: () {
                    final value = controller.text.trim();
                    if (value.length != 4) {
                      setSheetState(
                        () => error = l10n.chattttMinorModePinError,
                      );
                      return;
                    }
                    if (verify != null && !verify(value)) {
                      setSheetState(
                        () =>
                            error = errorText ?? l10n.chattttMinorModePinError,
                      );
                      return;
                    }
                    Navigator.of(sheetContext).pop(value);
                  },
                  child: Text(confirmLabel),
                ),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => Navigator.of(sheetContext).pop(),
                child: Text(l10n.chattttMinorModeCancel),
              ),
            ],
          ),
        ),
      ),
    );
    controller.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final colors = context.appColors;

    Widget feature({
      required IconData icon,
      required String title,
      required String desc,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: cs.onSurface.withValues(alpha: 0.06),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 19,
                color: cs.onSurface.withValues(alpha: 0.82),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: AppFontWeights.semibold,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    desc,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: cs.onSurface.withValues(alpha: 0.56),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text(l10n.chattttMinorMode),
      ),
      body: !_loaded
          ? const SizedBox.shrink()
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                    children: [
                      const SizedBox(height: 12),
                      Center(
                        child: Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            color: colors.surfaceCard,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: colors.hairline,
                              width: 0.8,
                            ),
                          ),
                          child: Icon(
                            Icons.umbrella_outlined,
                            size: 48,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(height: 26),
                      Text(
                        _enabled
                            ? l10n.chattttMinorModeEnabledTitle
                            : l10n.chattttMinorMode,
                        style: TextStyle(
                          fontSize: 26,
                          height: 1.15,
                          fontWeight: AppFontWeights.emphasis,
                          letterSpacing: -0.4,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _enabled
                            ? l10n.chattttMinorModeEnabledDesc
                            : l10n.chattttMinorModeIntro,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.65,
                          color: cs.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(height: 30),
                      feature(
                        icon: Icons.visibility_outlined,
                        title: l10n.chattttMinorModeAgeTitle,
                        desc: l10n.chattttMinorModeAgeDesc,
                      ),
                      feature(
                        icon: Icons.lock_outline_rounded,
                        title: l10n.chattttMinorModeGuardianTitle,
                        desc: l10n.chattttMinorModeGuardianDesc,
                      ),
                      feature(
                        icon: Icons.devices_outlined,
                        title: l10n.chattttMinorModeSyncTitle,
                        desc: l10n.chattttMinorModeSyncDesc,
                      ),
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: SizedBox(
                      height: 52,
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _handleAction,
                        style: FilledButton.styleFrom(
                          backgroundColor: cs.onSurface,
                          foregroundColor: cs.surface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                          textStyle: TextStyle(
                            fontSize: 16,
                            fontWeight: AppFontWeights.semibold,
                          ),
                        ),
                        child: Text(
                          _enabled
                              ? l10n.chattttMinorModeDisable
                              : l10n.chattttMinorModeStart,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
