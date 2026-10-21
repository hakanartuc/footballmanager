import 'package:flutter/material.dart';

import '../../engine/engine_gateway.dart';
import '../../l10n/generated/app_localizations.dart';

/// A failed action: a short localized message, the raw message folded
/// under details, and a retry button.
class ErrorCard extends StatelessWidget {
  const ErrorCard({super.key, required this.error, required this.onRetry});

  final GatewayError error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final message = switch (error.kind) {
      GatewayErrorKind.save => l.loadError,
      _ => l.error,
    };
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.error, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(message),
            ExpansionTile(
              title: Text(l.errorDetails),
              tilePadding: EdgeInsets.zero,
              children: [SelectableText(error.message)],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(onPressed: onRetry, child: Text(l.retry)),
            ),
          ],
        ),
      ),
    );
  }
}
