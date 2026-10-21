import 'package:engine/engine.dart';
import 'package:flutter/material.dart';

import '../../engine/snapshots.dart';
import '../../l10n/generated/app_localizations.dart';
import '../widgets/club_chip.dart';

/// Shows a played [row]: both clubs, the score and the scorers by side.
Future<void> showMatchResultSheet(
  BuildContext context,
  FixtureRow row, {
  required ClubRef home,
  required ClubRef away,
}) => showModalBottomSheet<void>(
  context: context,
  builder: (context) => _MatchResult(row: row, home: home, away: away),
);

class _MatchResult extends StatelessWidget {
  const _MatchResult({
    required this.row,
    required this.home,
    required this.away,
  });

  final FixtureRow row;
  final ClubRef home;
  final ClubRef away;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final text = Theme.of(context).textTheme;
    Widget club(ClubRef c) => Column(
      children: [
        ClubChip(c, compact: true),
        const SizedBox(height: 4),
        Text(c.name, textAlign: TextAlign.center, style: text.titleSmall),
      ],
    );
    Widget scorers(ClubId clubId, CrossAxisAlignment align) => Column(
      crossAxisAlignment: align,
      children: [
        for (final g in row.goals)
          if (g.clubId == clubId) Text("${g.minute}' ${g.scorerName}"),
      ],
    );
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(child: club(home)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    '${row.homeGoals ?? 0} - ${row.awayGoals ?? 0}',
                    style: text.displaySmall,
                  ),
                ),
                Expanded(child: club(away)),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: scorers(home.id, CrossAxisAlignment.start)),
                const SizedBox(width: 12),
                Expanded(child: scorers(away.id, CrossAxisAlignment.end)),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l.ok),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
