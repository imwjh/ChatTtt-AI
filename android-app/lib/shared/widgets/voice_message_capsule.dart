import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../icons/lucide_adapter.dart';
import '../../l10n/app_localizations.dart';
import 'audio_clip_player.dart';
import 'ios_tactile.dart';
import 'snackbar.dart';

/// 胶囊语音条：与文本气泡同样式的纯胶囊外壳，内部是播放按钮、起伏声波和时长。
///
/// 用户消息使用纯黑底 + 纯白内容，与文本气泡保持一致；助手消息跟随主题。
class VoiceMessageCapsule extends StatefulWidget {
  const VoiceMessageCapsule({
    super.key,
    required this.path,
    this.durationHint,
    this.isUser = false,
  });

  final String path;

  /// 文件名里记录的录音时长，播放器加载完成前先用它展示。
  final Duration? durationHint;

  final bool isUser;

  @override
  State<VoiceMessageCapsule> createState() => _VoiceMessageCapsuleState();
}

class _VoiceMessageCapsuleState extends State<VoiceMessageCapsule>
    with SingleTickerProviderStateMixin {
  final Object _owner = Object();
  late final AnimationController _wave = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1150),
  );

  @override
  void initState() {
    super.initState();
    AudioClipPlayback.instance.status.addListener(_syncWaveAnimation);
    _syncWaveAnimation();
  }

  @override
  void didUpdateWidget(covariant VoiceMessageCapsule oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      unawaited(AudioClipPlayback.instance.stopFor(_owner));
      _syncWaveAnimation();
    }
  }

  @override
  void dispose() {
    AudioClipPlayback.instance.status.removeListener(_syncWaveAnimation);
    unawaited(AudioClipPlayback.instance.stopFor(_owner));
    _wave.dispose();
    super.dispose();
  }

  bool get _playing {
    final status = AudioClipPlayback.instance.status.value;
    return status != null && identical(status.owner, _owner) && status.playing;
  }

  void _syncWaveAnimation() {
    if (_playing) {
      if (!_wave.isAnimating) _wave.repeat();
    } else if (_wave.isAnimating) {
      _wave.stop();
    }
  }

  Future<void> _toggle() async {
    try {
      await AudioClipPlayback.instance.toggle(owner: _owner, path: widget.path);
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: AppLocalizations.of(context)!.audioClipPlaybackFailed,
        type: NotificationType.error,
      );
    }
    _syncWaveAnimation();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;

    final Color background = widget.isUser
        ? const Color(0xFF000000)
        : (isDark
              ? theme.colorScheme.onSurface.withValues(alpha: 0.08)
              : theme.colorScheme.surface);
    final Color foreground = widget.isUser
        ? const Color(0xFFFFFFFF)
        : theme.colorScheme.onSurface;
    final Border? border = widget.isUser
        ? (isDark
              ? Border.all(
                  color: Colors.white.withValues(alpha: 0.12),
                  width: 0.8,
                )
              : null)
        : Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.18),
          );
    final Color buttonBackground = widget.isUser
        ? Colors.white.withValues(alpha: 0.18)
        : theme.colorScheme.onSurface.withValues(alpha: isDark ? 0.12 : 0.06);

    return ValueListenableBuilder<AudioClipStatus?>(
      valueListenable: AudioClipPlayback.instance.status,
      builder: (context, status, _) {
        final mine = status != null && identical(status.owner, _owner)
            ? status
            : null;
        final playing = mine?.playing ?? false;
        final position = mine?.position ?? Duration.zero;
        final total = mine?.duration ?? widget.durationHint;
        final totalMs = total?.inMilliseconds ?? 0;
        final progress = totalMs <= 0
            ? 0.0
            : (position.inMilliseconds / totalMs).clamp(0.0, 1.0).toDouble();
        final timeLabel = total == null ? '--:--' : formatClipDuration(total);

        return Container(
          width: 150,
          padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(999),
            border: border,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: buttonBackground,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: IosIconButton(
                    icon: playing ? Lucide.Pause : Lucide.Play,
                    size: 15,
                    padding: EdgeInsets.zero,
                    visualSize: 30,
                    borderRadius: 999,
                    color: foreground,
                    pressedColor: foreground.withValues(alpha: 0.7),
                    tooltip: playing
                        ? l10n.audioClipPauseTooltip
                        : l10n.audioClipPlayTooltip,
                    onTap: () => unawaited(_toggle()),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 18,
                  child: AnimatedBuilder(
                    animation: _wave,
                    builder: (context, _) => CustomPaint(
                      painter: _VoiceWavePainter(
                        color: foreground,
                        progress: progress,
                        phase: _wave.value,
                        animate: playing,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                timeLabel,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.1,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: foreground.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 竖条声波：未播放时平缓，播放时随时间起伏，已播放部分高亮。
class _VoiceWavePainter extends CustomPainter {
  const _VoiceWavePainter({
    required this.color,
    required this.progress,
    required this.phase,
    required this.animate,
  });

  final Color color;
  final double progress;
  final double phase;
  final bool animate;

  static const List<double> _pattern = <double>[
    0.35,
    0.55,
    0.8,
    0.45,
    0.7,
    1.0,
    0.6,
    0.4,
    0.75,
    0.9,
    0.5,
    0.3,
    0.65,
    0.85,
    0.55,
    0.4,
    0.7,
    0.95,
    0.6,
    0.45,
    0.8,
    0.5,
    0.35,
    0.6,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    const double barWidth = 2.2;
    const double minHeight = 3;
    final int count = math.max(2, (size.width / 4.2).round());
    final double step = (size.width - barWidth) / (count - 1);
    final Paint paint = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < count; i++) {
      final double base = _pattern[i % _pattern.length];
      final double factor;
      if (animate) {
        final double wobble = math.sin((phase * 2 * math.pi) + i * 0.62);
        factor = (base * (0.72 + 0.28 * wobble)).clamp(0.12, 1.0).toDouble();
      } else {
        factor = 0.2 + base * 0.5;
      }
      final double height = (minHeight + (size.height - minHeight) * factor)
          .clamp(minHeight, size.height)
          .toDouble();
      final double left = i * step;
      final double top = (size.height - height) / 2;
      final bool played = (i + 0.5) / count <= progress;
      paint.color = color.withValues(
        alpha: played ? 1.0 : (animate ? 0.34 : 0.46),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, top, barWidth, height),
          const Radius.circular(barWidth / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_VoiceWavePainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.progress != progress ||
      oldDelegate.phase != phase ||
      oldDelegate.animate != animate;
}
