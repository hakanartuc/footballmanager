import 'dart:convert';

import '../model/enums.dart';
import 'assets_embedded.dart';

List<String> _strings(dynamic l) => [for (final e in l as List) e as String];

/// The climates a country can have; they key the match-day weather tables.
const climates = [
  'temperate',
  'mediterranean',
  'continental',
  'tropical',
  'arid',
];

/// One division of a country's league pyramid; `tiers[0]` is the top flight.
class TierTemplate {
  int clubs;
  int promoted;
  int relegated;

  /// Localisation key for the league name, e.g. "tier1".
  String nameKey;

  TierTemplate({
    required this.clubs,
    required this.promoted,
    required this.relegated,
    required this.nameKey,
  });

  factory TierTemplate.fromJson(Map<String, dynamic> j) => TierTemplate(
    clubs: j['clubs'] as int,
    promoted: j['promoted'] as int,
    relegated: j['relegated'] as int,
    nameKey: j['nameKey'] as String,
  );
}

/// A real country the world generator fills with fictional clubs.
class CountryTemplate {
  String code;
  String name;
  Continent continent;
  String namePool;
  List<TierTemplate> tiers;

  /// 1..100.
  int reputation;

  /// One of [climates].
  String climate;

  /// JSON key `south`, absent means false.
  bool southernHemisphere;

  CountryTemplate({
    required this.code,
    required this.name,
    required this.continent,
    required this.namePool,
    required this.tiers,
    required this.reputation,
    required this.climate,
    this.southernHemisphere = false,
  });

  factory CountryTemplate.fromJson(Map<String, dynamic> j) => CountryTemplate(
    code: j['code'] as String,
    name: j['name'] as String,
    continent: Continent.values.byName(j['continent'] as String),
    namePool: j['namePool'] as String,
    tiers: [
      for (final t in j['tiers'] as List)
        TierTemplate.fromJson(t as Map<String, dynamic>),
    ],
    reputation: j['reputation'] as int,
    climate: j['climate'] as String,
    southernHemisphere: j['south'] as bool? ?? false,
  );
}

/// Names for one country. Club and stadium patterns contain `{City}`.
class NamePool {
  List<String> firstNames;
  List<String> lastNames;
  List<String> cityNames;
  List<String> clubSuffixes;
  List<String> stadiumPatterns;

  NamePool({
    required this.firstNames,
    required this.lastNames,
    required this.cityNames,
    required this.clubSuffixes,
    required this.stadiumPatterns,
  });

  factory NamePool.fromJson(Map<String, dynamic> j) => NamePool(
    firstNames: _strings(j['firstNames']),
    lastNames: _strings(j['lastNames']),
    cityNames: _strings(j['cityNames']),
    clubSuffixes: _strings(j['clubSuffixes']),
    stadiumPatterns: _strings(j['stadiumPatterns']),
  );
}

/// The raw material of the world: country templates and name pools, parsed
/// from the JSON assets embedded in `assets_embedded.dart`.
class CountryData {
  List<CountryTemplate> countries;

  /// Keyed by pool name, e.g. "tr".
  Map<String, NamePool> pools;

  CountryData({required this.countries, required this.pools});

  static CountryData load() {
    final root = jsonDecode(embeddedAssets['countries.json']!) as Map;
    return CountryData(
      countries: [
        for (final c in root['countries'] as List)
          CountryTemplate.fromJson(c as Map<String, dynamic>),
      ],
      pools: {
        for (final MapEntry(:key, :value) in embeddedAssets.entries)
          if (key.startsWith('names/'))
            key.substring('names/'.length, key.length - '.json'.length):
                NamePool.fromJson(jsonDecode(value) as Map<String, dynamic>),
      },
    );
  }

  /// Human-readable problems; empty when the data is consistent.
  List<String> validate() {
    final problems = <String>[];
    final codes = <String>{};
    for (final c in countries) {
      if (!codes.add(c.code)) problems.add('duplicate country code ${c.code}');
      if (!pools.containsKey(c.namePool)) {
        problems.add('${c.code}: missing name pool "${c.namePool}"');
      }
      if (c.tiers.isEmpty) problems.add('${c.code}: no tiers');
      if (!climates.contains(c.climate)) {
        problems.add('${c.code}: unknown climate "${c.climate}"');
      }
      for (var i = 0; i < c.tiers.length; i++) {
        final t = c.tiers[i];
        final at = '${c.code} ${t.nameKey}';
        if (t.clubs < 12) problems.add('$at: ${t.clubs} clubs, need >= 12');
        if (i == 0 && t.promoted != 0) {
          problems.add('$at: promoted ${t.promoted} in the top tier');
        }
        if (i > 0 && t.promoted != c.tiers[i - 1].relegated) {
          problems.add(
            '$at: promoted ${t.promoted} != '
            'relegated ${c.tiers[i - 1].relegated} from the tier above',
          );
        }
        if (i == c.tiers.length - 1 && t.relegated != 0) {
          problems.add('$at: relegated ${t.relegated} from the bottom tier');
        }
      }
    }
    pools.forEach((name, p) {
      void atLeast(String what, List<String> l, int n) {
        if (l.length < n) problems.add('pool $name: $what ${l.length} < $n');
      }

      atLeast('firstNames', p.firstNames, 60);
      atLeast('lastNames', p.lastNames, 80);
      atLeast('cityNames', p.cityNames, 40);
      atLeast('clubSuffixes', p.clubSuffixes, 4);
      atLeast('stadiumPatterns', p.stadiumPatterns, 3);
    });
    return problems;
  }
}
