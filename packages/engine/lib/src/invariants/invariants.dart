import '../core/ids.dart';
import '../model/enums.dart';
import '../model/events.dart';
import '../model/world.dart';
import '../sim/day_loop.dart';
import '../sim/lineup.dart';

/// One broken world invariant: [rule] is the rule id (e.g. `player.oneClub`)
/// and [detail] says where.
class Violation {
  final String rule;
  final String detail;

  const Violation(this.rule, this.detail);

  @override
  String toString() => '$rule: $detail';
}

/// Every invariant [w] breaks. Empty for a consistent world.
///
/// Single pass each over clubs, players, fixtures, inbox and history; meant
/// to run every simulated day.
List<Violation> checkInvariants(World w) {
  final out = <Violation>[];
  _checkIds(w, out);
  final index = _checkClubs(w, out);
  _checkPlayers(w, index, out);
  _checkFixtures(w, out);
  _checkInbox(w, out);
  _checkHistory(w, out);
  return out;
}

/// `ids.unique`: every map key equals its value's id.
void _checkIds(World w, List<Violation> out) {
  void check<T>(String kind, Map<int, T> map, int Function(T) idOf) {
    for (final MapEntry(:key, :value) in map.entries) {
      if (key != idOf(value)) {
        out.add(
          Violation('ids.unique', '$kind key $key holds id ${idOf(value)}'),
        );
      }
    }
  }

  check('player', w.players, (p) => p.id);
  check('club', w.clubs, (c) => c.id);
  check('league', w.leagues, (l) => l.id);
  check('country', w.countries, (c) => c.id);
  check('manager', w.managers, (m) => m.id);
  check('fixture', w.fixtures, (f) => f.id);
}

/// `squad.size`, `lineup.valid`, `manager.seat`. Returns the reverse squad
/// index: player id to (club id, isYouth) from the clubs' squad views.
Map<PlayerId, (ClubId, bool)> _checkClubs(World w, List<Violation> out) {
  final index = <PlayerId, (ClubId, bool)>{};
  for (final club in w.clubs.values) {
    final squad = w.squadOf(club.id);
    if (squad.length < 18 || squad.length > 28) {
      out.add(
        Violation('squad.size', 'club ${club.id} has ${squad.length} seniors'),
      );
    }
    for (final (youth, ids) in [(false, squad), (true, w.youthOf(club.id))]) {
      for (final p in ids) {
        final prev = index[p];
        if (prev != null) {
          out.add(
            Violation(
              'player.oneClub',
              'player $p in squads of clubs ${prev.$1} and ${club.id}',
            ),
          );
        }
        index[p] = (club.id, youth);
      }
    }

    final lineup = club.lineup;
    if (lineup != null) {
      final errors = validateLineup(w, club.id, lineup);
      if (errors.isNotEmpty) {
        out.add(
          Violation(
            'lineup.valid',
            'club ${club.id}: ${errors.map((e) => e.name).join(', ')}',
          ),
        );
      }
    }

    final managerId = club.managerId;
    final manager = managerId == null ? null : w.managers[managerId];
    if (managerId == null) {
      out.add(Violation('manager.seat', 'club ${club.id} has no manager'));
    } else if (manager == null) {
      out.add(
        Violation('manager.seat', 'club ${club.id} manager $managerId missing'),
      );
    } else if (manager.clubId != club.id) {
      out.add(
        Violation(
          'manager.seat',
          'club ${club.id} manager $managerId is at ${manager.clubId}',
        ),
      );
    }
  }
  for (final m in w.managers.values) {
    final clubId = m.clubId;
    if (clubId != null && w.clubs[clubId]?.managerId != m.id) {
      out.add(
        Violation(
          'manager.seat',
          'manager ${m.id} at club $clubId not seated there',
        ),
      );
    }
  }
  final user = w.managers[w.userManagerId];
  if (user == null || !user.isUser) {
    out.add(
      Violation(
        'manager.seat',
        'user manager ${w.userManagerId} missing or not isUser',
      ),
    );
  }
  return index;
}

/// `player.oneClub`, `player.ranges`, `contract.dates`.
void _checkPlayers(
  World w,
  Map<PlayerId, (ClubId, bool)> index,
  List<Violation> out,
) {
  final yesterday = w.date.addDays(-1);
  for (final p in w.players.values) {
    final contract = p.contract;
    final seat = index[p.id];
    if (contract == null) {
      if (seat != null) {
        out.add(
          Violation(
            'player.oneClub',
            'free agent ${p.id} in squad of club ${seat.$1}',
          ),
        );
      }
    } else {
      if (!w.clubs.containsKey(contract.clubId)) {
        out.add(
          Violation(
            'player.oneClub',
            'player ${p.id} contracted to missing club ${contract.clubId}',
          ),
        );
      } else if (seat != (contract.clubId, p.isYouth)) {
        out.add(
          Violation(
            'player.oneClub',
            'player ${p.id} contracted to club ${contract.clubId} (youth: ${p.isYouth}) but indexed at $seat',
          ),
        );
      }
      if (!contract.end.isAfter(contract.start) ||
          contract.end.isBefore(yesterday)) {
        out.add(
          Violation(
            'contract.dates',
            'player ${p.id} contract ${contract.start.iso}..${contract.end.iso} on ${w.date.iso}',
          ),
        );
      }
    }

    for (final a in Attr.values) {
      final v = p.attrs[a];
      if (v < 1 || v > 20) {
        out.add(Violation('player.ranges', 'player ${p.id} ${a.name} = $v'));
      }
    }
    if (p.ca < 1 || p.ca > p.pa || p.pa > 200) {
      out.add(
        Violation('player.ranges', 'player ${p.id} ca ${p.ca} pa ${p.pa}'),
      );
    }
    final age = p.ageAt(w.date);
    if (age < 15 || age > 45) {
      out.add(Violation('player.ranges', 'player ${p.id} age $age'));
    }
    final s = p.state;
    for (final (name, v) in [
      ('condition', s.condition),
      ('morale', s.morale),
      ('sharpness', s.sharpness),
    ]) {
      if (v < 0 || v > 100) {
        out.add(Violation('player.ranges', 'player ${p.id} $name = $v'));
      }
    }
  }
}

/// `league.fixtures`, `fixture.goals`, `calendar.noDoubleBooking`,
/// `fixture.result`, all for the current season.
void _checkFixtures(World w, List<Violation> out) {
  final members = {for (final l in w.leagues.values) l.id: l.clubIds.toSet()};
  final pairs = {
    for (final l in w.leagues.values) l.id: <(ClubId, ClubId), int>{},
  };
  final booked = <(ClubId, int)>{};

  for (final f in w.fixtures.values) {
    if (f.seasonYear != w.seasonYear) continue;
    final clubs = members[f.leagueId];
    if (clubs == null) {
      out.add(
        Violation(
          'league.fixtures',
          'fixture ${f.id} in unknown league ${f.leagueId}',
        ),
      );
      continue;
    }
    for (final c in [f.homeId, f.awayId]) {
      if (!clubs.contains(c)) {
        out.add(
          Violation(
            'league.fixtures',
            'fixture ${f.id}: club $c not in league ${f.leagueId}',
          ),
        );
      }
      if (!booked.add((c, f.date.dayIndex))) {
        out.add(
          Violation(
            'calendar.noDoubleBooking',
            'club $c has two fixtures on ${f.date.iso}',
          ),
        );
      }
    }
    final key = (f.homeId, f.awayId);
    pairs[f.leagueId]![key] = (pairs[f.leagueId]![key] ?? 0) + 1;

    final r = f.result;
    if (r != null) {
      var home = 0, away = 0;
      for (final g in r.goals) {
        if (g.clubId == f.homeId) {
          home++;
        } else if (g.clubId == f.awayId) {
          away++;
        } else {
          out.add(
            Violation(
              'fixture.goals',
              'fixture ${f.id}: goal by club ${g.clubId} not in the fixture',
            ),
          );
        }
        if (!w.players.containsKey(g.scorerId)) {
          out.add(
            Violation(
              'fixture.goals',
              'fixture ${f.id}: scorer ${g.scorerId} missing',
            ),
          );
        }
      }
      if (home != r.homeGoals || away != r.awayGoals) {
        out.add(
          Violation(
            'fixture.goals',
            'fixture ${f.id}: goal events $home-$away, result ${r.homeGoals}-${r.awayGoals}',
          ),
        );
      }
    }
    final played = r != null;
    if (f.date.isBefore(w.date) != played) {
      out.add(
        Violation(
          'fixture.result',
          'fixture ${f.id} on ${f.date.iso} ${played ? 'has' : 'lacks'} a result on ${w.date.iso}',
        ),
      );
    }
  }

  for (final l in w.leagues.values) {
    final counts = pairs[l.id]!;
    for (final a in l.clubIds) {
      for (final b in l.clubIds) {
        if (a == b) continue;
        final n = counts[(a, b)] ?? 0;
        if (n != 1) {
          out.add(
            Violation(
              'league.fixtures',
              'league ${l.id}: $a v $b scheduled $n times',
            ),
          );
        }
      }
    }
  }
}

/// `inbox.size`, `inbox.ids` (unique and positive), `inbox.refs` (clubs,
/// leagues and fixtures; player ids are exempt because players leave the
/// world).
void _checkInbox(World w, List<Violation> out) {
  if (w.inbox.length > inboxLimit) {
    out.add(Violation('inbox.size', '${w.inbox.length} messages'));
  }
  final seen = <int>{};
  for (final m in w.inbox) {
    if (m.id <= 0) {
      out.add(Violation('inbox.ids', 'message id ${m.id} is not positive'));
    } else if (!seen.add(m.id)) {
      out.add(Violation('inbox.ids', 'message id ${m.id} is duplicated'));
    }
    void club(ClubId? id) {
      if (id != null && !w.clubs.containsKey(id)) {
        out.add(
          Violation(
            'inbox.refs',
            '${m.event.runtimeType} on ${m.date.iso}: club $id missing',
          ),
        );
      }
    }

    void league(LeagueId id) {
      if (!w.leagues.containsKey(id)) {
        out.add(
          Violation(
            'inbox.refs',
            '${m.event.runtimeType} on ${m.date.iso}: league $id missing',
          ),
        );
      }
    }

    switch (m.event) {
      case MatchPlayed(:final fixtureId):
        if (!w.fixtures.containsKey(fixtureId)) {
          out.add(
            Violation(
              'inbox.refs',
              'MatchPlayed on ${m.date.iso}: fixture $fixtureId missing',
            ),
          );
        }
      case LeagueChampion(:final leagueId, :final clubId):
        league(leagueId);
        club(clubId);
      case Promoted(:final clubId, :final fromLeagueId, :final toLeagueId):
      case Relegated(:final clubId, :final fromLeagueId, :final toLeagueId):
        club(clubId);
        league(fromLeagueId);
        league(toLeagueId);
      case PlayerRetired(:final clubId):
        club(clubId);
      // Player ids are not checked: the players may have retired or been
      // released since the message was written.
      case YouthIntake(:final clubId):
      case YouthReleased(:final clubId):
        club(clubId);
      case SeasonEnded() || NewSeasonStarted():
        break;
    }
  }
}

/// `history.champion`: every league in either map has a champion equal to
/// the first of its final order.
void _checkHistory(World w, List<Violation> out) {
  for (final a in w.history) {
    for (final l in {...a.champions.keys, ...a.finalOrder.keys}) {
      final champion = a.champions[l];
      final first = a.finalOrder[l]?.firstOrNull;
      if (first != champion) {
        out.add(
          Violation(
            'history.champion',
            'season ${a.seasonYear} league $l: champion $champion, table leader $first',
          ),
        );
      }
    }
  }
}
