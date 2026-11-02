import 'dart:math' as math;

import '../core/ids.dart';
import '../model/events.dart';
import '../model/fixture.dart';
import '../model/match_rules.dart';
import '../model/player.dart';
import '../model/world.dart';

/// Post-match and daily constants of the discipline, injury and form
/// bookkeeping (spec 6.3, 8.6). Match-time constants live in
/// `EngineTuning`.
abstract final class DisciplineTuning {
  /// Players older than [injuryAgeDays] heal ×[injuryAgeMul] slower.
  static const int injuryAgeDays = 30;
  static const double injuryAgeMul = 1.15;

  /// Sharpness on the day an injury heals.
  static const double returnSharpness = 40;

  /// Sharpness gained per appearance and per day (capped at 100).
  static const double sharpnessPerMatch = 5;
  static const double sharpnessPerDay = 1;

  /// Weight of the latest rating in the form average.
  static const double formWeight = 0.2;
}

/// The bookkeeping after [f] was played with result [r] under [rules].
///
/// Appearances (starters of both stored lineups plus every substitute
/// brought on), goals and assists from the [Goal] events (an own goal
/// credits nobody), yellows and reds, `ratingSum`, form and sharpness are
/// season/state credits and are skipped for an abandoned match. What
/// happened on the pitch is kept either way: yellow accumulation (a ban
/// of `i + 1` matches at the i-th of `rules.yellowThresholds`), a second
/// yellow (`rules.redBanSecondYellow`, not counted as a yellow), a
/// straight red (`rules.redBanViolent` for violent conduct, else
/// `rules.redBanFoul`), injuries (days ×[DisciplineTuning.injuryAgeMul]
/// over [DisciplineTuning.injuryAgeDays]; the medical facility arrives in
/// Faz 5) and the final condition of everyone in a match squad.
/// Bans add to any ban the player is already serving.
///
/// Form is spec 8.6's "average of the last five ratings" approximated by
/// an exponential moving average with weight [DisciplineTuning.formWeight].
///
/// Returns the day events ([PlayerSentOff], [PlayerSuspended],
/// [PlayerInjured]) in the order of `r.events`.
List<GameEvent> applyPostMatch(
  World w,
  Fixture f,
  MatchResult r,
  MatchRules rules,
) {
  final out = <GameEvent>[];
  final credit = !r.abandoned;
  final appeared = <PlayerId>{
    for (final c in [f.homeId, f.awayId]) ...?w.clubs[c]?.lineup?.starters,
    for (final e in r.events)
      if (e is Substitution) e.inId,
  };

  for (final e in r.events) {
    switch (e) {
      case Goal(:final scorerId, :final assistId, :final isOwnGoal):
        if (!credit || isOwnGoal) break;
        w.players[scorerId]!.season.goals++;
        if (assistId != null) w.players[assistId]!.season.assists++;
      case Booking(:final playerId, :final clubId, :final kind, :final reason):
        final p = w.players[playerId]!;
        switch (kind) {
          case CardKind.yellow:
            if (credit) p.season.yellows++;
            p.state.yellowCards++;
            final i = rules.yellowThresholds.indexOf(p.state.yellowCards);
            if (i != -1) _ban(w, out, p, clubId, i + 1);
          case CardKind.secondYellow:
            if (credit) p.season.reds++;
            out.add(
              PlayerSentOff(
                date: w.date,
                playerId: playerId,
                clubId: clubId,
                fixtureId: f.id,
              ),
            );
            _ban(w, out, p, clubId, rules.redBanSecondYellow);
          case CardKind.red:
            if (credit) p.season.reds++;
            out.add(
              PlayerSentOff(
                date: w.date,
                playerId: playerId,
                clubId: clubId,
                fixtureId: f.id,
              ),
            );
            _ban(
              w,
              out,
              p,
              clubId,
              reason == FoulKind.violent
                  ? rules.redBanViolent
                  : rules.redBanFoul,
            );
        }
      case Injury(:final playerId, :final clubId, :final injury):
        final p = w.players[playerId]!;
        final mul = p.ageAt(w.date) > DisciplineTuning.injuryAgeDays
            ? DisciplineTuning.injuryAgeMul
            : 1.0;
        final days = (injury.daysLeft * mul).ceil();
        p.state.injury = InjuryStub(daysLeft: days, type: injury.type);
        out.add(
          PlayerInjured(
            date: w.date,
            playerId: playerId,
            clubId: clubId,
            days: days,
          ),
        );
      default:
        break;
    }
  }

  if (credit) {
    for (final id in appeared.toList()..sort()) {
      final p = w.players[id]!;
      p.season.apps++;
      p.state.sharpness = math.min(
        100,
        p.state.sharpness + DisciplineTuning.sharpnessPerMatch,
      );
    }
    for (final id in r.ratings.keys.toList()..sort()) {
      final p = w.players[id]!;
      final rating = r.ratings[id]!;
      p.season.ratingSum += rating;
      p.state.form =
          p.state.form * (1 - DisciplineTuning.formWeight) +
          rating * DisciplineTuning.formWeight;
    }
  }

  for (final id in r.finalCondition.keys.toList()..sort()) {
    w.players[id]!.state.condition = r.finalCondition[id]!;
  }
  return out;
}

void _ban(World w, List<GameEvent> out, Player p, ClubId clubId, int matches) {
  p.state.suspensionMatches += matches;
  out.add(
    PlayerSuspended(
      date: w.date,
      playerId: p.id,
      clubId: clubId,
      matches: matches,
    ),
  );
}

/// The daily injury and sharpness update, players in id order: an injury
/// counts down a day and, at zero, heals with sharpness
/// [DisciplineTuning.returnSharpness]; everyone else gains
/// [DisciplineTuning.sharpnessPerDay] (capped at 100). Suspensions are
/// served per match in `DayRunner.playMatches`, not here.
void dailyRecovery(World w) {
  for (final id in w.players.keys.toList()..sort()) {
    final s = w.players[id]!.state;
    final injury = s.injury;
    if (injury != null && --injury.daysLeft <= 0) {
      s.injury = null;
      s.sharpness = DisciplineTuning.returnSharpness;
    } else {
      s.sharpness = math.min(
        100,
        s.sharpness + DisciplineTuning.sharpnessPerDay,
      );
    }
  }
}
