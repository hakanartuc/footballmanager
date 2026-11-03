import '../core/ids.dart';
import '../core/rng.dart';
import '../data/country_data.dart';
import '../model/club.dart';
import '../model/enums.dart';
import '../model/tactic.dart';
import 'player_generator.dart';

/// Kit palette (ARGB). It contains both white and black, so every colour
/// has at least one palette colour with a luminance difference >= 0.4.
const List<int> kitPalette = [
  0xFFD62828, // red
  0xFF1F4FD1, // blue
  0xFFFFFFFF, // white
  0xFF000000, // black
  0xFFFFD500, // yellow
  0xFF1E8C3A, // green
  0xFF7A1F3D, // claret
  0xFF6EC1E4, // sky blue
  0xFFF77F00, // orange
  0xFF5E2B97, // purple
  0xFF0B1F5C, // navy
  0xFF800000, // maroon
  0xFF008080, // teal
  0xFFC9A227, // gold
  0xFFF48FB1, // pink
  0xFF8A8A8A, // grey
];

/// Relative luminance in 0..1 on plain sRGB channels (no gamma), which is
/// enough to tell shirt colours apart.
double kitLuminance(int argb) {
  final r = (argb >> 16) & 0xFF;
  final g = (argb >> 8) & 0xFF;
  final b = argb & 0xFF;
  return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;
}

/// Builds clubs from a [NamePool]; every random draw comes from [_rng].
class ClubGenerator {
  ClubGenerator(this._pool, this._rng, this._ids);

  final NamePool _pool;
  final SeededRng _rng;
  final IdAllocator _ids;

  /// A club at 0-based reputation rank [indexInLeague] of a [tier] league
  /// of [leagueSize] clubs. The name is unique against [usedNames], which
  /// it is added to.
  Club generate({
    required CountryId countryId,
    required LeagueId leagueId,
    required int tier,
    required int countryReputation,
    required int indexInLeague,
    required int leagueSize,
    required Set<String> usedNames,
  }) {
    final reputation = _reputation(
      countryReputation,
      tier,
      indexInLeague,
      leagueSize,
    );
    final (city, name) = _uniqueName(usedNames);
    usedNames.add(name);

    final homePrimary = _rng.pick(kitPalette);
    final homeSecondary = _contrasting(homePrimary);
    final awayPrimary = _contrasting(homePrimary);
    final awaySecondary = _contrasting(awayPrimary);

    final meanWage = wageForCa((reputation * 1.3 + 30).round());
    final transferBudget = reputation * reputation * 100;
    int facility() =>
        ((reputation / 10).round() + _rng.nextInt(3) - 1).clamp(1, 10);

    return Club(
      id: _ids.next('club'),
      name: name,
      shortName: city.substring(0, 3).toUpperCase(),
      countryId: countryId,
      leagueId: leagueId,
      reputation: reputation,
      home: Kit(primary: homePrimary, secondary: homeSecondary),
      away: Kit(primary: awayPrimary, secondary: awaySecondary),
      logo: LogoSpec(
        shape: _rng.nextInt(8),
        color1: homePrimary,
        color2: homeSecondary,
      ),
      stadiumName: _rng.pick(_pool.stadiumPatterns).replaceAll('{City}', city),
      stadiumCapacity: _capacity(tier, reputation),
      balance: transferBudget,
      transferBudget: transferBudget,
      wageBudget: (24 * meanWage * 1.1).round(),
      facilities: Facilities(
        training: facility(),
        medical: facility(),
        youth: facility(),
      ),
      expectation: switch (indexInLeague) {
        <= 1 => BoardExpectation.title,
        <= 5 => BoardExpectation.top,
        <= 9 => BoardExpectation.upperMid,
        <= 13 => BoardExpectation.mid,
        _ => BoardExpectation.avoidRelegation,
      },
      tactics: defaultTactics(Formation.f442),
    );
  }

  /// Tier 1 runs from `countryRep + 5` (rank 0) linearly down to
  /// `countryRep − 25` (last rank); tier 2 is 25 lower, tier 3 40 lower.
  static int _reputation(int countryRep, int tier, int index, int size) {
    final tier1 = countryRep + 5 - index * (30 / (size - 1));
    final offset = switch (tier) {
      1 => 0,
      2 => 25,
      _ => 40,
    };
    return (tier1 - offset).round().clamp(5, 100);
  }

  /// A `(city, name)` pair whose name is not in [used]; up to 50 draws.
  (String, String) _uniqueName(Set<String> used) {
    for (var i = 0; i < 50; i++) {
      final city = _rng.pick(_pool.cityNames);
      final name = _rng.pick(_pool.clubSuffixes).replaceAll('{City}', city);
      if (!used.contains(name)) return (city, name);
    }
    throw StateError('no unused club name found in 50 draws');
  }

  /// A random palette colour other than [against] whose luminance differs
  /// from it by at least 0.4.
  int _contrasting(int against) {
    final lum = kitLuminance(against);
    final candidates = [
      for (final c in kitPalette)
        if (c != against && (kitLuminance(c) - lum).abs() >= 0.4) c,
    ];
    return _rng.pick(candidates);
  }

  /// Linear in reputation within the tier's band: tier 1 25k..60k over
  /// rep 30..100, tier 2 8k..25k over rep 5..75, tier 3 3k..10k over 5..60.
  static int _capacity(int tier, int rep) {
    final (lo, hi, repLo, repHi) = switch (tier) {
      1 => (25000, 60000, 30, 100),
      2 => (8000, 25000, 5, 75),
      _ => (3000, 10000, 5, 60),
    };
    final t = (rep - repLo) / (repHi - repLo);
    return (lo + (t * (hi - lo)).round()).clamp(lo, hi);
  }
}
