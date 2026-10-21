import 'package:engine/engine.dart';
import 'package:flutter/material.dart';

import '../../l10n/formatters.dart';

/// A compact rounded label with [position]'s code.
class PositionChip extends StatelessWidget {
  const PositionChip(this.position, {super.key});

  final Position position;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 44,
      padding: const EdgeInsets.symmetric(vertical: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        positionCode(position),
        style: TextStyle(
          color: scheme.onSecondaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
