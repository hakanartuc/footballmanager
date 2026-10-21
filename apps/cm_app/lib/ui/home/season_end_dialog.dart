import 'package:flutter/material.dart';

import '../../l10n/formatters.dart';
import '../../l10n/generated/app_localizations.dart';

/// Announces the end of the season starting in [seasonYear], with the
/// user's [finalPosition] in the league when they had a club.
Future<void> showSeasonEndDialog(
  BuildContext context, {
  required int seasonYear,
  int? finalPosition,
}) {
  final l = AppLocalizations.of(context)!;
  final season = seasonLabel(seasonYear);
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l.seasonEnded),
      content: Text(
        finalPosition == null
            ? l.seasonEndBodyUnemployed(season)
            : l.seasonEndBody(season, finalPosition),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.ok),
        ),
      ],
    ),
  );
}
