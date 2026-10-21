import 'package:flutter/material.dart';

import '../../engine/snapshots.dart';
import '../theme.dart';

/// A club's two kit colours as a split circle, followed by its short name
/// unless [compact].
class ClubChip extends StatelessWidget {
  const ClubChip(this.ref, {super.key, this.compact = false});

  final ClubRef ref;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final primary = kitColor(ref.kitPrimary);
    final secondary = kitColor(ref.kitSecondary);
    final circle = Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        gradient: LinearGradient(
          colors: [primary, primary, secondary, secondary],
          stops: const [0, 0.5, 0.5, 1],
        ),
      ),
    );
    if (compact) return circle;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [circle, const SizedBox(width: 6), Text(ref.shortName)],
    );
  }
}
