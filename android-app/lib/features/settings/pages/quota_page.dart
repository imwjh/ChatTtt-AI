import 'package:flutter/material.dart';

import '../../../core/services/usage/usage_quota_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_back_button.dart';
import '../../../shared/widgets/ios_settings_rows.dart';
import '../../../shared/widgets/section_card.dart';
import '../../../theme/app_font_weights.dart';
import '../../../theme/app_semantic_colors.dart';

/// 免费额度与用量页（本地展示）。
class QuotaPage extends StatefulWidget {
  const QuotaPage({super.key});

  @override
  State<QuotaPage> createState() => _QuotaPageState();
}

class _QuotaPageState extends State<QuotaPage> {
  final UsageQuotaService _quota = UsageQuotaService.instance;

  @override
  void initState() {
    super.initState();
    _quota.addListener(_onChanged);
    _quota.ensureLoaded();
  }

  @override
  void dispose() {
    _quota.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final colors = context.appColors;
    final days = _quota.lastDays(7);
    final maxCount = days.fold<int>(1, (max, item) {
      return item.count > max ? item.count : max;
    });
    final usedPercent = _quota.used / UsageQuotaService.monthlyQuota * 100;
    final remainingPercent = (100 - usedPercent).clamp(0.0, 100.0).toDouble();
    final todayPercent =
        _quota.todayCount / UsageQuotaService.monthlyQuota * 100;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text(l10n.chattttQuotaPageTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _QuotaHeroCard(
            quota: _quota,
            usedPercent: usedPercent,
            remainingPercent: remainingPercent,
          ),
          const SizedBox(height: 12),
          SectionCard(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    Text(
                      l10n.chattttQuotaLast7Days,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: AppFontWeights.semibold,
                        color: cs.onSurface,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _formatPercent(usedPercent),
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 132,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var i = 0; i < days.length; i++) ...[
                        if (i > 0) const SizedBox(width: 10),
                        Expanded(
                          child: _UsageBar(
                            label: _dayLabel(days[i].day),
                            ratio: days[i].count / maxCount,
                            highlight: i == days.length - 1,
                            trackColor: colors.surfaceFill,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SectionCard(
            children: [
              IosNavRow(
                icon: Icons.today_outlined,
                label: l10n.chattttQuotaToday,
                detailText: _formatPercent(todayPercent),
              ),
              const IosRowDivider(),
              IosNavRow(
                icon: Icons.data_usage_outlined,
                label: l10n.chattttQuotaTotal,
                detailText: '100.0%',
              ),
            ],
          ),
          IosSectionFooter(text: l10n.chattttQuotaHint),
          IosSectionFooter(text: l10n.chattttQuotaResetHint),
        ],
      ),
    );
  }

  static String _dayLabel(DateTime day) => '${day.month}/${day.day}';

  static String _formatPercent(num value) => '${value.toStringAsFixed(1)}%';
}

class _QuotaHeroCard extends StatelessWidget {
  const _QuotaHeroCard({
    required this.quota,
    required this.usedPercent,
    required this.remainingPercent,
  });

  final UsageQuotaService quota;
  final double usedPercent;
  final double remainingPercent;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.hairline, width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.chattttQuotaUsed,
            style: TextStyle(
              fontSize: 13,
              color: cs.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                usedPercent.toStringAsFixed(1),
                style: TextStyle(
                  fontSize: 34,
                  height: 1.05,
                  fontWeight: AppFontWeights.semibold,
                  letterSpacing: -0.6,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '%',
                style: TextStyle(
                  fontSize: 16,
                  color: cs.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: quota.progress,
              minHeight: 8,
              backgroundColor: cs.onSurface.withValues(alpha: 0.08),
              valueColor: AlwaysStoppedAnimation<Color>(cs.onSurface),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                '${l10n.chattttQuotaRemaining} '
                '${remainingPercent.toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withValues(alpha: 0.55),
                ),
              ),
              const Spacer(),
              Text(
                '${l10n.chattttQuotaTotal} 100.0%',
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _UsageBar extends StatelessWidget {
  const _UsageBar({
    required this.label,
    required this.ratio,
    required this.highlight,
    required this.trackColor,
  });

  final String label;
  final double ratio;
  final bool highlight;
  final Color trackColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final target = (ratio.clamp(0.0, 1.0) * 76).clamp(4.0, 76.0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween<double>(end: target),
          duration: const Duration(milliseconds: 520),
          curve: Curves.easeOutCubic,
          builder: (context, height, _) => Container(
            height: 80,
            alignment: Alignment.bottomCenter,
            decoration: BoxDecoration(
              color: trackColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Container(
              width: double.infinity,
              height: height,
              decoration: BoxDecoration(
                color: cs.onSurface.withValues(alpha: highlight ? 0.9 : 0.55),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          maxLines: 1,
          style: TextStyle(
            fontSize: 10,
            color: cs.onSurface.withValues(alpha: 0.45),
          ),
        ),
      ],
    );
  }
}
