import 'dart:async';
import 'dart:io';
import 'package:Kelivo/theme/app_font_weights.dart';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../icons/lucide_adapter.dart';
import 'package:provider/provider.dart';
import '../../../core/chatttt/chatttt_config.dart';
import '../../../core/chatttt/chatttt_service.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_back_button.dart';
import '../../../shared/widgets/ios_switch.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../core/services/haptics.dart';
import 'debug_page.dart';
import '../../dev/pages/markdown_playground_page.dart';
import 'log_viewer_page.dart';
import 'package:Kelivo/shared/widgets/section_card.dart';
import 'package:Kelivo/theme/app_semantic_colors.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String _version = '';
  String _buildNumber = '';
  String _systemInfo = '';
  int _versionTapCount = 0;
  DateTime? _lastVersionTap;
  int _appNameTapCount = 0;
  DateTime? _lastAppNameTap;
  bool _connected = ChatTttService.instance.isConnected;
  StreamSubscription<bool>? _connectionSubscription;

  @override
  void initState() {
    super.initState();
    _loadInfo();
    _connectionSubscription = ChatTttService.instance.connection.listen((
      value,
    ) {
      if (!mounted) return;
      setState(() => _connected = value);
    });
  }

  @override
  void dispose() {
    _connectionSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadInfo() async {
    final pkg = await PackageInfo.fromPlatform();
    String sys;
    if (Platform.isAndroid) {
      sys = 'Android';
    } else if (Platform.isIOS) {
      sys = 'iOS';
    } else if (Platform.isMacOS) {
      sys = 'macOS';
    } else if (Platform.isWindows) {
      sys = 'Windows';
    } else if (Platform.isLinux) {
      sys = 'Linux';
    } else {
      sys = Platform.operatingSystem;
    }
    setState(() {
      _version = pkg.version;
      _buildNumber = pkg.buildNumber;
      _systemInfo = sys;
    });
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      // Fallback: try in-app web view
      await launchUrl(uri, mode: LaunchMode.platformDefault);
    }
  }

  Future<void> _onAppNameTap() async {
    final now = DateTime.now();
    if (_lastAppNameTap == null ||
        now.difference(_lastAppNameTap!) > const Duration(seconds: 2)) {
      _appNameTapCount = 0;
    }
    _lastAppNameTap = now;
    _appNameTapCount++;
    if (_appNameTapCount < 7) return;

    _appNameTapCount = 0;
    Haptics.medium();
    final added = await context.read<SettingsProvider>().unlockKelivoSearch();
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    showAppSnackBar(
      context,
      message: added
          ? l10n.aboutPageKelivoSearchUnlocked
          : l10n.aboutPageKelivoSearchAlreadyUnlocked,
      type: NotificationType.success,
    );
  }

  void _onVersionTap() {
    final now = DateTime.now();
    // Reset the counter if taps are spaced too far apart
    if (_lastVersionTap == null ||
        now.difference(_lastVersionTap!) > const Duration(seconds: 2)) {
      _versionTapCount = 0;
    }
    _lastVersionTap = now;
    _versionTapCount++;

    const threshold = 7;
    if (_versionTapCount < threshold) return;

    _versionTapCount = 0; // reset after unlock
    _showEasterEgg();
  }

  void _showEasterEgg() {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: BoxConstraints(
        minWidth: MediaQuery.of(context).size.width,
        maxWidth: MediaQuery.of(context).size.width,
      ),
      backgroundColor: context.overlaySurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogContext, dialogSetState) {
            return SafeArea(
              child: FractionallySizedBox(
                heightFactor: 0.7,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(Lucide.Sparkles, size: 28, color: cs.primary),
                      const SizedBox(height: 16),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            children: [
                              if (Platform.isAndroid || Platform.isIOS) ...[
                                const SizedBox(height: 24),
                                const Divider(),
                                const SizedBox(height: 16),
                                Material(
                                  color: Colors.transparent,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 6,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            l10n.contextLogSettingTitle,
                                            style: TextStyle(
                                              color: cs.onSurface.withValues(
                                                alpha: 0.9,
                                              ),
                                            ),
                                          ),
                                        ),
                                        InkWell(
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                          onTap: () {
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    const LogViewerPage(
                                                      initialTab: LogViewerPage
                                                          .contextTab,
                                                    ),
                                              ),
                                            );
                                          },
                                          child: Padding(
                                            padding: const EdgeInsets.all(6),
                                            child: Icon(
                                              Lucide.FolderOpen,
                                              size: 20,
                                              color: cs.primary,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        IosSwitch(
                                          value: dialogContext
                                              .watch<SettingsProvider>()
                                              .contextLogEnabled,
                                          onChanged: (v) => dialogContext
                                              .read<SettingsProvider>()
                                              .setContextLogEnabled(v),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    l10n.contextLogSettingSubtitle,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: cs.onSurface.withValues(
                                        alpha: 0.65,
                                      ),
                                      height: 1.25,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Material(
                                  color: Colors.transparent,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 6,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            l10n.requestLogSettingTitle,
                                            style: TextStyle(
                                              color: cs.onSurface.withValues(
                                                alpha: 0.9,
                                              ),
                                            ),
                                          ),
                                        ),
                                        InkWell(
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                          onTap: () {
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    const LogViewerPage(
                                                      initialTab: LogViewerPage
                                                          .requestTab,
                                                    ),
                                              ),
                                            );
                                          },
                                          child: Padding(
                                            padding: const EdgeInsets.all(6),
                                            child: Icon(
                                              Lucide.FolderOpen,
                                              size: 20,
                                              color: cs.primary,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        IosSwitch(
                                          value: dialogContext
                                              .watch<SettingsProvider>()
                                              .requestLogEnabled,
                                          onChanged: (v) => dialogContext
                                              .read<SettingsProvider>()
                                              .setRequestLogEnabled(v),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    l10n.requestLogSettingSubtitle,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: cs.onSurface.withValues(
                                        alpha: 0.65,
                                      ),
                                      height: 1.25,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Material(
                                  color: Colors.transparent,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 6,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            l10n.flutterLogSettingTitle,
                                            style: TextStyle(
                                              color: cs.onSurface.withValues(
                                                alpha: 0.9,
                                              ),
                                            ),
                                          ),
                                        ),
                                        InkWell(
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                          onTap: () {
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    const LogViewerPage(
                                                      initialTab:
                                                          LogViewerPage.appTab,
                                                    ),
                                              ),
                                            );
                                          },
                                          child: Padding(
                                            padding: const EdgeInsets.all(6),
                                            child: Icon(
                                              Lucide.FolderOpen,
                                              size: 20,
                                              color: cs.primary,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        IosSwitch(
                                          value: dialogContext
                                              .watch<SettingsProvider>()
                                              .flutterLogEnabled,
                                          onChanged: (v) => dialogContext
                                              .read<SettingsProvider>()
                                              .setFlutterLogEnabled(v),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    l10n.flutterLogSettingSubtitle,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: cs.onSurface.withValues(
                                        alpha: 0.65,
                                      ),
                                      height: 1.25,
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 24),
                              const Divider(),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () => Navigator.of(ctx).maybePop(),
                        child: Text(l10n.aboutPageEasterEggButton),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _openDebugPage() {
    Haptics.medium();
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const DebugPage()));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text(l10n.settingsPageAbout),
        actions: const [SizedBox(width: 12)],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        children: [
          // Header card: left icon + right title/description
          SectionCard(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onLongPress: _openDebugPage,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          width: 54,
                          height: 54,
                          child: Image.asset(
                            'assets/app_icon.png',
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _onAppNameTap,
                            child: Text(
                              'ChatTtt',
                              key: const ValueKey('about-page-app-name'),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: AppFontWeights.semibold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            l10n.chattttSettingsFooter,
                            style: TextStyle(
                              fontSize: 13,
                              color: cs.onSurface.withValues(alpha: 0.65),
                              height: 1.2,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // iOS-style list card
          SectionCard(
            children: [
              if (kDebugMode || kProfileMode) ...[
                _iosNavRow(
                  context,
                  icon: Lucide.Code,
                  label: l10n.markdownPlaygroundTitle,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const MarkdownPlaygroundPage(),
                    ),
                  ),
                ),
                _iosDivider(context),
              ],
              // Version (tap 7x to unlock easter egg) — logic unchanged
              _iosNavRow(
                context,
                icon: Lucide.Code,
                label: l10n.aboutPageVersion,
                detailBuilder: (_) => Text(
                  _version.isEmpty ? '...' : '$_version / $_buildNumber',
                ),
                onTap: _onVersionTap,
              ),
              _iosDivider(context),
              _iosNavRow(
                context,
                icon: Lucide.Phone,
                label: l10n.aboutPageSystem,
                detailBuilder: (_) =>
                    Text(_systemInfo.isEmpty ? '...' : _systemInfo),
                onTap: null, // informational only
              ),
              _iosDivider(context),
              _iosNavRow(
                context,
                icon: Lucide.Earth,
                label: l10n.aboutPageWebsite,
                onTap: () async {
                  final uri = Uri.parse('https://chatttt.imwjh.com');
                  if (!await launchUrl(uri, mode: LaunchMode.platformDefault)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
              ),
              _iosDivider(context),
              _iosNavRowSvgLeading(
                context,
                svgAsset: 'assets/icons/github.svg',
                label: l10n.aboutPageGithub,
                onTap: () => _openUrl('https://github.com/imwjh/ChatTtt-AI'),
              ),
              _iosDivider(context),
              _iosNavRow(
                context,
                icon: Lucide.FileText,
                label: l10n.aboutPageLicense,
                onTap: () =>
                    _openUrl('https://www.gnu.org/licenses/agpl-3.0.html'),
              ),
            ],
          ),

          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: Text(
              l10n.chattttAboutServiceSection,
              style: TextStyle(
                fontSize: 13,
                fontWeight: AppFontWeights.semibold,
                color: cs.onSurface.withValues(alpha: 0.8),
              ),
            ),
          ),
          SectionCard(
            children: [
              _iosNavRow(
                context,
                icon: Icons.link,
                label: l10n.chattttSettingsServiceAddress,
                detailText: _serviceLabel(
                  ChatTttConfig.instance.serverUrl,
                  l10n,
                ),
                onTap: () => _editServerUrl(context),
              ),
              _iosDivider(context),
              _iosNavRow(
                context,
                icon: Icons.cloud_outlined,
                label: l10n.chattttSettingsServiceStatus,
                detailText: _connected
                    ? l10n.chattttSettingsConnected
                    : l10n.chattttSettingsDisconnected,
                onTap: null,
              ),
            ],
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  static String _serviceLabel(String? url, AppLocalizations l10n) {
    if (url == null || url.isEmpty) {
      return l10n.chattttSettingsServiceAddressUnset;
    }
    final host = Uri.tryParse(url)?.host ?? '';
    return host.isEmpty ? url : host;
  }

  Future<void> _editServerUrl(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final config = ChatTttConfig.instance;
    final controller = TextEditingController(text: config.serverUrl ?? '');
    final result = await showDialog<String>(
      context: context,
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
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(999),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(999),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(999),
                  borderSide: BorderSide(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.4),
                  ),
                ),
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
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.chattttServerCancel),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: Text(l10n.chattttServerSave),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.isEmpty) return;

    await config.setServerUrl(result);
    final url = config.serverUrl;
    var reachable = false;
    if (url != null && url.isNotEmpty) {
      try {
        await ChatTttService.instance.ensureConnected(url);
        reachable = true;
      } catch (_) {
        reachable = false;
      }
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
}

// --- iOS-style helpers (mirroring Settings/Display pages) ---

Widget _iosDivider(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return Divider(
    height: 6,
    thickness: 0.6,
    indent: 54,
    endIndent: 12,
    color: cs.outlineVariant.withValues(alpha: 0.18),
  );
}

class _AnimatedPressColor extends StatelessWidget {
  const _AnimatedPressColor({
    required this.pressed,
    required this.base,
    required this.builder,
  });
  final bool pressed;
  final Color base;
  final Widget Function(Color color) builder;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final target = pressed
        ? (Color.lerp(base, cs.surface, 0.55) ?? base)
        : base;
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: target),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, color, _) => builder(color ?? base),
    );
  }
}

class _TactileRow extends StatefulWidget {
  const _TactileRow({
    required this.builder,
    this.onTap,
    this.pressedScale = 1.00,
    this.haptics = false,
  });
  final Widget Function(bool pressed) builder;
  final VoidCallback? onTap;
  final double pressedScale;
  final bool haptics;
  @override
  State<_TactileRow> createState() => _TactileRowState();
}

class _TactileRowState extends State<_TactileRow> {
  bool _pressed = false;
  void _setPressed(bool v) {
    if (_pressed != v) {
      setState(() => _pressed = v);
    }
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.builder(_pressed);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null ? null : (_) => _setPressed(true),
      onTapUp: widget.onTap == null ? null : (_) => _setPressed(false),
      onTapCancel: widget.onTap == null ? null : () => _setPressed(false),
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.haptics &&
                  context.read<SettingsProvider>().hapticsOnListItemTap) {
                Haptics.soft();
              }
              widget.onTap!.call();
            },
      child: widget.pressedScale == 1.0
          ? child
          : AnimatedScale(
              scale: _pressed ? widget.pressedScale : 1.0,
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOutCubic,
              child: child,
            ),
    );
  }
}

Widget _iosNavRow(
  BuildContext context, {
  required IconData icon,
  required String label,
  VoidCallback? onTap,
  String? detailText,
  Widget Function(BuildContext ctx)? detailBuilder,
}) {
  final cs = Theme.of(context).colorScheme;
  final interactive = onTap != null;
  return _TactileRow(
    onTap: onTap,
    pressedScale: 1.00, // list rows: color shift only, no scale
    haptics: false,
    builder: (pressed) {
      final baseColor = cs.onSurface.withValues(alpha: 0.9);
      return _AnimatedPressColor(
        pressed: pressed,
        base: baseColor,
        builder: (c) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                SizedBox(width: 36, child: Icon(icon, size: 20, color: c)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 15, color: c),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (detailBuilder != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: DefaultTextStyle(
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurface.withValues(alpha: 0.6),
                      ),
                      child: detailBuilder(context),
                    ),
                  )
                else if (detailText != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(
                      detailText,
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                if (interactive) Icon(Lucide.ChevronRight, size: 16, color: c),
              ],
            ),
          );
        },
      );
    },
  );
}

Widget _iosNavRowSvgLeading(
  BuildContext context, {
  required String svgAsset,
  required String label,
  VoidCallback? onTap,
  String? detailText,
  Widget Function(BuildContext ctx)? detailBuilder,
}) {
  final cs = Theme.of(context).colorScheme;
  final interactive = onTap != null;
  return _TactileRow(
    onTap: onTap,
    pressedScale: 1.00,
    haptics: false,
    builder: (pressed) {
      final baseColor = cs.onSurface.withValues(alpha: 0.9);
      return _AnimatedPressColor(
        pressed: pressed,
        base: baseColor,
        builder: (c) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                SizedBox(
                  width: 36,
                  child: SvgPicture.asset(
                    svgAsset,
                    width: 20,
                    height: 20,
                    colorFilter: ColorFilter.mode(c, BlendMode.srcIn),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 15, color: c),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (detailBuilder != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: DefaultTextStyle(
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurface.withValues(alpha: 0.6),
                      ),
                      child: detailBuilder(context),
                    ),
                  )
                else if (detailText != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(
                      detailText,
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                if (interactive) Icon(Lucide.ChevronRight, size: 16, color: c),
              ],
            ),
          );
        },
      );
    },
  );
}
