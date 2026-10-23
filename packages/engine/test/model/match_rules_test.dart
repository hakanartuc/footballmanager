import 'dart:convert';

import 'package:engine/engine.dart';
import 'package:test/test.dart';

void main() {
  test('league rules have the documented defaults', () {
    const r = MatchRules.league;
    expect(r.substitutions, 5);
    expect(r.benchSize, 7);
    expect(r.extraTime, isFalse);
    expect(r.penalties, isFalse);
    expect(r.yellowThresholds, [5, 10, 15]);
    expect(r.redBanSecondYellow, 1);
    expect(r.redBanFoul, 3);
    expect(r.redBanViolent, 4);
  });

  test('JSON round trip keeps every field in declaration order', () {
    const r = MatchRules(
      substitutions: 3,
      benchSize: 9,
      extraTime: true,
      penalties: true,
      yellowThresholds: [4, 8],
      redBanSecondYellow: 2,
      redBanFoul: 4,
      redBanViolent: 6,
    );
    final j = matchRulesToJson(r);
    expect(j.keys, [
      'substitutions',
      'benchSize',
      'extraTime',
      'penalties',
      'yellowThresholds',
      'redBanSecondYellow',
      'redBanFoul',
      'redBanViolent',
    ]);
    final back = matchRulesFromJson(
      jsonDecode(jsonEncode(j)) as Map<String, dynamic>,
    );
    expect(matchRulesToJson(back), j);
  });

  test('a league defaults to league rules and round-trips them', () {
    final l = League(
      id: 1,
      countryId: 1,
      tier: 1,
      name: 'L',
      clubIds: [],
      promotedCount: 0,
      relegatedCount: 3,
      reputation: 50,
    );
    expect(identical(l.rules, MatchRules.league), isTrue);
    final j = leagueToJson(l);
    expect(j.keys.last, 'rules');
    expect(j['rules'], matchRulesToJson(MatchRules.league));
    final back = leagueFromJson(
      jsonDecode(jsonEncode(j)) as Map<String, dynamic>,
    );
    expect(matchRulesToJson(back.rules), matchRulesToJson(MatchRules.league));
  });

  test('a country round-trips its climate', () {
    final c = Country(
      id: 1,
      code: 'X',
      name: 'X',
      continent: Continent.europe,
      namePool: 'x',
      tiers: [],
      climate: 'arid',
    );
    final j = countryToJson(c);
    expect(j['climate'], 'arid');
    expect(countryFromJson(j).climate, 'arid');
  });
}
