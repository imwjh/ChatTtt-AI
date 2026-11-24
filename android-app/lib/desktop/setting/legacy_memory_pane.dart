import 'package:flutter/material.dart';

import '../../features/settings/pages/legacy_memory_page.dart';
import '../../icons/lucide_adapter.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/ios_tactile.dart';
import '../../theme/app_font_weights.dart';

/// Desktop right-side pane for read-only legacy memories (§14.5).
class DesktopLegacyMemoryPane extends StatelessWidget {
  const DesktopLegacyMemoryPane({super.key, this.assistantId});

  /// When set, only legacy memories of that assistant are listed.
  final String? assistantId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.legacyMemoryPageTitle,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: AppFontWeights.semibold,
                    color: cs.onSurface,
                  ),
                ),
              ),
              Tooltip(
                message: l10n.legacyMemoryExport,
                child: IosIconButton(
                  icon: Lucide.Share2,
                  color: cs.onSurface,
                  size: 18,
                  minSize: 36,
                  onTap: () => LegacyMemoryContent.exportAll(
                    context,
                    assistantId: assistantId,
                  ),
                ),
              ),
              Tooltip(
                message: l10n.legacyMemoryMigrate,
                child: IosIconButton(
                  icon: Lucide.Import,
                  color: cs.primary,
                  size: 18,
                  minSize: 36,
                  semanticLabel: l10n.legacyMemoryMigrate,
                  onTap: () => LegacyMemoryContent.showMigration(
                    context,
                    assistantId: assistantId,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: LegacyMemoryContent(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            assistantId: assistantId,
          ),
        ),
      ],
    );
  }
}
