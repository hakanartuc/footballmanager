import 'dart:convert';
import 'dart:isolate';

import 'package:engine/engine.dart';
import 'package:test/test.dart';

const _days = 120;
const _lineupDay = 2; // zero-based: the third advanced day

/// A small world from seed 7 with the user at the first TR tier-1 club.
EngineSession _newSession() {
  NewGameSpec spec(ClubId? club) => NewGameSpec(
    seed: 7,
    size: WorldSize.small,
    managerFirstName: 'Det',
    managerLastName: 'Erminist',
    managerCountryCode: 'TR',
    startClubId: club,
  );
  final probe = createNewGame(spec(null));
  final tr = probe.countries.values.firstWhere((c) => c.code == 'TR');
  final club = probe.leagues[tr.tiers[0]]!.clubIds[0];
  return EngineSession.newGame(spec(club));
}

Lineup _copy(Lineup l) => Lineup(
  formation: l.formation,
  starters: [...l.starters],
  bench: [...l.bench],
);

/// Advances [s] by [days] days, applying `SetLineup(lineup)` for the user
/// club on day [_lineupDay]. A null [lineup] is picked by [autoLineup]
/// from [s]'s own world that morning; the lineup used is returned.
Lineup _advance(EngineSession s, int days, [Lineup? lineup]) {
  final club = s.world.userClub!.id;
  for (var day = 0; day < days; day++) {
    if (day == _lineupDay) {
      lineup ??= autoLineup(s.world, club);
      s.advanceDay([SetLineup(clubId: club, lineup: _copy(lineup))]);
    } else {
      s.advanceDay();
    }
  }
  return lineup!;
}

String _json(World w) => jsonEncode(worldToJson(w));

void main() {
  test('two sessions from the same seed and commands give the same world', () {
    final a = _newSession();
    final lineup = _advance(a, _days);
    final b = _newSession();
    _advance(b, _days, lineup);
    expect(_json(b.world), _json(a.world));
  });

  test('the same run in another isolate gives the same world', () async {
    final a = _newSession();
    final lineup = _advance(a, _days);
    final other = await Isolate.run(() {
      final s = _newSession();
      _advance(s, _days, lineup);
      return _json(s.world);
    });
    expect(other, _json(a.world));
  });

  test('a session restored from a mid-run save continues identically', () {
    final a = _newSession();
    final lineup = _advance(a, _days ~/ 2);
    final c = EngineSession.fromBytes(a.save());
    expect(_json(c.world), _json(a.world));
    for (final s in [a, c]) {
      for (var day = _days ~/ 2; day < _days; day++) {
        s.advanceDay();
      }
    }
    expect(_json(c.world), _json(a.world));
    // The restored run matches a fresh uninterrupted run too.
    final b = _newSession();
    _advance(b, _days, lineup);
    expect(_json(c.world), _json(b.world));
  });
}
