import '../model/enums.dart';
import '../model/json.dart';
import '../model/match_rules.dart';
import 'save_codec.dart';

/// Upgrades a save envelope from schema [from] to `from + 1`.
///
/// [apply] receives and returns the whole envelope map
/// (`{"schemaVersion": from, "world": {...}}`); [migrate] sets the new
/// `schemaVersion` afterwards.
class Migration {
  final int from;
  final Map<String, dynamic> Function(Map<String, dynamic>) apply;

  const Migration({required this.from, required this.apply});
}

/// The registered migrations, one per schema step.
const List<Migration> migrations = [
  Migration(from: 1, apply: _v1InboxIds),
  Migration(from: 2, apply: _migrate2to3),
];

/// v1 -> v2: inbox messages get ids `1..n` in stored order (v1 entries
/// have none) and `ids.inbox` becomes `n`, the last issued id.
Map<String, dynamic> _v1InboxIds(Map<String, dynamic> envelope) {
  final world = envelope['world'] as Map<String, dynamic>;
  var n = 0;
  world['inbox'] = [
    for (final m in world['inbox'] as List)
      {'id': ++n, ...m as Map<String, dynamic>},
  ];
  final ids = world['ids'] as Map<String, dynamic>? ?? <String, dynamic>{};
  ids['inbox'] = n;
  world['ids'] = ids;
  return envelope;
}

/// v2 -> v3 (Faz 1a): clubs carry tactics, leagues match rules and
/// countries a climate. Later v3 additions go in their own helpers called
/// from here.
Map<String, dynamic> _migrate2to3(Map<String, dynamic> envelope) {
  final world = envelope['world'] as Map<String, dynamic>;
  for (final club in (world['clubs'] as Map<String, dynamic>).values) {
    _addClubTactics(club as Map<String, dynamic>);
  }
  for (final league in (world['leagues'] as Map<String, dynamic>).values) {
    _addLeagueRules(league as Map<String, dynamic>);
  }
  for (final country in (world['countries'] as Map<String, dynamic>).values) {
    _addCountryClimate(country as Map<String, dynamic>);
  }
  return envelope;
}

/// Gives a league without `rules` the default league rules.
void _addLeagueRules(Map<String, dynamic> league) {
  league['rules'] ??= matchRulesToJson(MatchRules.league);
}

/// Gives a country without `climate` the temperate climate.
void _addCountryClimate(Map<String, dynamic> country) {
  country['climate'] ??= 'temperate';
}

/// Replaces a club's `formation` with three balanced preset tactics
/// (`'1'` on the old formation, `'2'` 4-3-3, `'3'` 5-3-2) and
/// `activeTactic: 0`.
void _addClubTactics(Map<String, dynamic> club) {
  final formation = club.remove('formation') as String;
  club['tactics'] = [
    _presetTacticJson('1', formation),
    _presetTacticJson('2', 'f433'),
    _presetTacticJson('3', 'f532'),
  ];
  club['activeTactic'] = 0;
}

/// The v3 JSON of a balanced preset tactic, keys in `Tactic` field order.
Map<String, dynamic> _presetTacticJson(String name, String formation) => {
  'name': name,
  'formation': formation,
  'slots': [
    for (final p in formationSlots(Formation.values.byName(formation))) p.name,
  ],
  'mentality': 'balanced',
  'passing': 'mixed',
  'tempo': 'normal',
  'width': 'normal',
  'pressing': 'normal',
  'tackling': 'normal',
  'marking': 'zonal',
  'offsideTrap': false,
  'counterAttack': false,
  'playmaker': null,
  'targetMan': null,
  'captain': null,
  'viceCaptain': null,
  'setPieces': <String, dynamic>{
    'cornerLeft': null,
    'cornerRight': null,
    'freeKickLeft': null,
    'freeKickRight': null,
    'penalty': null,
    'longThrow': null,
  },
  'instructions': <String, dynamic>{},
  'arrows': <String, dynamic>{},
};

/// Applies the migrations of [registry] (default [migrations]) in order until
/// [envelope] is at [currentSchemaVersion].
///
/// Throws [SaveError] `newerSchema` when the envelope is newer than this
/// engine and `corrupt` when a step is missing.
Map<String, dynamic> migrate(
  Map<String, dynamic> envelope, {
  List<Migration>? registry,
}) {
  final steps = registry ?? migrations;
  var version = envelope['schemaVersion'] as int;
  if (version > currentSchemaVersion) {
    throw SaveError(
      SaveErrorKind.newerSchema,
      'save is schema v$version, engine supports v$currentSchemaVersion',
    );
  }
  while (version < currentSchemaVersion) {
    final from = version;
    final step = steps.where((m) => m.from == from).firstOrNull;
    if (step == null) {
      throw SaveError(SaveErrorKind.corrupt, 'no migration from v$version');
    }
    envelope = step.apply(envelope);
    version = from + 1;
    envelope['schemaVersion'] = version;
  }
  return envelope;
}
