import 'package:flutter/material.dart';

/// A centred icon and [text] for an empty list.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.text,
    this.icon = Icons.inbox_outlined,
  });

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: color),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: color),
            ),
          ],
        ),
      ),
    );
  }
}
