import 'package:flutter/material.dart';

import '../../engine/snapshots.dart';
import '../../l10n/event_text.dart';
import '../../l10n/formatters.dart';
import '../../l10n/generated/app_localizations.dart';

/// One inbox message: its title, date and body.
class InboxDetailScreen extends StatelessWidget {
  const InboxDetailScreen(this.item, {super.key});

  final InboxItem item;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final text = EventText.describe(item, l);
    final theme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(text.title, overflow: TextOverflow.ellipsis)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            formatDate(item.date, Localizations.localeOf(context)),
            style: theme.labelLarge,
          ),
          const SizedBox(height: 12),
          Text(text.body, style: theme.bodyLarge),
        ],
      ),
    );
  }
}
