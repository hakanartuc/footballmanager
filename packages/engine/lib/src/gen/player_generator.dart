import 'dart:math' as math;

import '../core/game_date.dart';
import '../core/ids.dart';
import '../core/rng.dart';
import '../data/country_data.dart';
import '../model/attributes.dart';
import '../model/enums.dart';
import '../model/player.dart';

/// Weekly wage in abstract units for a player of ability [ca]:
/// `round(ca² × 0.9 / 1000) × 10` (ca 100 → 90, 150 → 200, 180 → 290).
int wageForCa(int ca) => (ca * ca * 0.9 / 1000).round() * 10;

/// Familiarity granted to positions adjacent to the main one; all other
/// positions get 1..5 and the main position 20.
const Map<Position, Map<Position, int>> _adjacent = {
  Position.dc: {Position.dl: 12, Position.dr: 12},
  Position.dl: {Position.dc: 12},
  Position.dr: {Position.dc: 12},
  Position.mc: {Position.dm: 14, Position.amc: 14},
  Position.dm: {Position.mc: 14},
  Position.amc: {Position.mc: 14, Position.st: 10},
  Position.ml: {Position.aml: 14},
  Position.aml: {Position.ml: 14},
  Position.mr: {Position.amr: 14},
  Position.amr: {Position.mr: 14},
  Position.st: {Position.amc: 10},
};

/// Builds players from a [NamePool]; every random draw comes from [_rng].
class PlayerGenerator {
  PlayerGenerator(this._pool, this._rng, this._ids);

  final NamePool _pool;
  final SeededRng _rng;
  final IdAllocator _ids;

  /// A player whose attributes are built around [targetCa]; the stored
  /// `ca` is recomputed from the attributes and may differ a little.
  /// A null [clubId] makes a free agent; otherwise a contract is attached
  /// with a provisional status ([PlayerStatus.firstTeam], or
  /// [PlayerStatus.youth] when [youth]).
  Player generate({
    required CountryId nationality,
    required Position position,
    required int targetCa,
    required int age,
    required GameDate today,
    required ClubId? clubId,
    bool youth = false,
  }) {
    final firstName = _rng.pick(_pool.firstNames);
    final lastName = _rng.pick(_pool.lastNames);
    final birth = _birthDate(age, today);
    final isGk = position == Position.gk;
    final heightCm = _rng
        .nextGaussian(mean: isGk ? 188 : 180, sd: isGk ? 6 : 7)
        .round()
        .clamp(160, 205);
    final attrs = _buildAttrs(targetCa, position);
    final ca = computeCa(attrs, position);
    final growth = _rng.nextGaussian(mean: (27 - age) * 4, sd: 10).round();
    final pa = math.max(ca, ca + growth).clamp(ca, 200);
    final familiarity = <Position, int>{
      for (final p in Position.values)
        p: p == position
            ? 20
            : _adjacent[position]?[p] ?? (1 + _rng.nextInt(5)),
    };
    final hidden = HiddenAttrs(
      injuryProneness: 1 + _rng.nextInt(20),
      consistency: 1 + _rng.nextInt(20),
      bigMatches: 1 + _rng.nextInt(20),
      professionalism: 1 + _rng.nextInt(20),
    );
    Contract? contract;
    if (clubId != null) {
      final years = 1 + _rng.nextInt(4);
      contract = Contract(
        clubId: clubId,
        wageWeekly: wageForCa(ca),
        start: today,
        end: GameDate.ymd(today.year + years, 6, 30),
        status: youth ? PlayerStatus.youth : PlayerStatus.firstTeam,
      );
    }
    return Player(
      id: _ids.next('player'),
      firstName: firstName,
      lastName: lastName,
      nationality: nationality,
      birth: birth,
      heightCm: heightCm,
      mainPosition: position,
      familiarity: familiarity,
      attrs: attrs,
      ca: ca,
      pa: pa,
      hidden: hidden,
      contract: contract,
      isYouth: youth,
    );
  }

  /// A senior player for a club of [clubReputation]: age triangular
  /// 18..34 (mode 25) unless [age] is given; CA gaussian around
  /// `clubReputation × 1.3 + 30` (sd 12, GK −5), clamped 30..190.
  Player generateForTier({
    required int clubReputation,
    required CountryId nationality,
    required Position position,
    required GameDate today,
    required ClubId? clubId,
    int? age,
  }) {
    final sampledAge = age ?? _triangularAge();
    final mean = clubReputation * 1.3 + 30 - (position == Position.gk ? 5 : 0);
    final targetCa = _rng
        .nextGaussian(mean: mean, sd: 12)
        .round()
        .clamp(30, 190);
    return generate(
      nationality: nationality,
      position: position,
      targetCa: targetCa,
      age: sampledAge,
      today: today,
      clubId: clubId,
    );
  }

  /// Triangular on [18, 35) with mode 25.5, floored: ages 18..34, mode 25.
  int _triangularAge() {
    const a = 18.0, b = 35.0, c = 25.5;
    final u = _rng.nextDouble();
    final x = u < (c - a) / (b - a)
        ? a + math.sqrt(u * (b - a) * (c - a))
        : b - math.sqrt((1 - u) * (b - a) * (b - c));
    return x.floor().clamp(18, 34);
  }

  /// [age] years before [today] (Feb 29 → Feb 28), minus 0..364 days, so
  /// the player is exactly [age] on [today].
  GameDate _birthDate(int age, GameDate today) {
    final day = today.month == 2 && today.day == 29 ? 28 : today.day;
    final anniversary = GameDate.ymd(today.year - age, today.month, day);
    return anniversary.addDays(-_rng.nextInt(365));
  }

  /// Attributes around `targetCa / 10`: attributes weighted for the
  /// position group sit at the base level, the rest 4 below it. GK
  /// outfield attributes are then squeezed into 3..8.
  Attributes _buildAttrs(int targetCa, Position position) {
    final base = targetCa / 10;
    final weights = caWeightsFor(position.group);
    final attrs = Attributes.filled(1);
    for (final a in Attr.values) {
      final v = (weights[a] ?? 0) > 0
          ? base + _rng.nextGaussian(sd: 1.2)
          : base - 4 + _rng.nextGaussian(sd: 2);
      attrs.set(a, v.round());
    }
    if (position == Position.gk) {
      for (final a in Attr.values) {
        if (!weights.containsKey(a)) attrs.set(a, attrs[a].clamp(3, 8));
      }
    }
    return attrs;
  }
}
