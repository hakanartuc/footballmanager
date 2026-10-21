import 'package:engine/engine.dart';
import 'package:flutter/material.dart';

import '../../engine/snapshots.dart';
import '../../state/game_controller.dart';
import 'match_result_sheet.dart';
import 'season_end_dialog.dart';

/// Shows [outcome]'s user match result sheet, then the season end dialog
/// when the season ended; nothing unless [controller] is [Ready].
///
/// The dialog's season is the refreshed home's season year minus one: the
/// rollover starts the next season on the day the old one ends. Its final
/// position is [positionBefore] (the home before the action, since the
/// refreshed home shows the next season's table); null leaves it out.
Future<void> presentOutcome(
  BuildContext context,
  GameController controller,
  AdvanceOutcome outcome, {
  int? positionBefore,
}) async {
  final state = controller.state;
  if (state is! Ready) return;
  final match = outcome.userMatch;
  if (match != null) {
    ClubRef club(ClubId id) => state.refs.clubs.firstWhere((c) => c.id == id);
    await showMatchResultSheet(
      context,
      match,
      home: club(match.homeId),
      away: club(match.awayId),
    );
    if (!context.mounted) return;
  }
  if (outcome.seasonEnded) {
    await showSeasonEndDialog(
      context,
      seasonYear: state.home.seasonYear - 1,
      finalPosition: positionBefore,
    );
  }
}
