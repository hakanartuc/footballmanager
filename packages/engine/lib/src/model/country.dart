import '../core/ids.dart';
import 'enums.dart';
import 'match_rules.dart';

class Country {
  CountryId id;
  String code;
  String name;
  Continent continent;
  String namePool;

  /// League ids by tier; `tiers[0]` is the top division.
  List<LeagueId> tiers;

  /// 'temperate', 'mediterranean', 'continental', 'tropical' or 'arid';
  /// drives match-day weather.
  String climate;

  Country({
    required this.id,
    required this.code,
    required this.name,
    required this.continent,
    required this.namePool,
    required this.tiers,
    this.climate = 'temperate',
  });
}

class League {
  LeagueId id;
  CountryId countryId;
  int tier;
  String name;
  List<ClubId> clubIds;
  int promotedCount;
  int relegatedCount;
  int reputation;
  MatchRules rules;

  League({
    required this.id,
    required this.countryId,
    required this.tier,
    required this.name,
    required this.clubIds,
    required this.promotedCount,
    required this.relegatedCount,
    required this.reputation,
    this.rules = MatchRules.league,
  });
}
