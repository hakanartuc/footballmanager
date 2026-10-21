import 'package:flutter/material.dart';

import '../../engine/engine_gateway.dart';
import '../../l10n/generated/app_localizations.dart';

/// A failed action: a short localized message, the raw message folded
/// under details, a retry button and, with [onDismiss], an ok button.
class ErrorCard extends StatelessWidget {
  const ErrorCard({
    super.key,
    required this.error,
    required this.onRetry,
    this.onDismiss,
  });

  final GatewayError error;
  final VoidCallback onRetry;
  final VoidCallback? onDismiss;

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
            OverflowBar(
              alignment: MainAxisAlignment.end,
              spacing: 8,
              children: [
                if (onDismiss != null)
                  TextButton(onPressed: onDismiss, child: Text(l.ok)),
                FilledButton(onPressed: onRetry, child: Text(l.retry)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
