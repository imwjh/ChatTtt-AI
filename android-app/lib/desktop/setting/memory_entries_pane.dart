import 'package:flutter/material.dart';

import '../../features/settings/pages/memory_entries_page.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_font_weights.dart';

/// Desktop right-side pane for the global memory list (§14.4).
class DesktopMemoryEntriesPane extends StatelessWidget {
  const DesktopMemoryEntriesPane({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Text(
            l10n.memoryEntriesPageTitle,
            style: TextStyle(
              fontSize: 18,
              fontWeight: AppFontWeights.semibold,
              color: cs.onSurface,
            ),
          ),
        ),
        const Expanded(
          child: MemoryEntriesContent(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
          ),
        ),
      ],
    );
  }
}
