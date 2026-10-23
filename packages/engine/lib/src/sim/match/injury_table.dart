import '../../core/rng.dart';
import '../../model/player.dart';
import 'tuning.dart';

/// Injury type keys per severity band of `EngineTuning.injuryBandDays`
/// (spec 6.2): minor, light, moderate, serious, severe.
const List<List<String>> injuryTypes = [
  ['bruise', 'sprain'],
  ['hamstring', 'groin', 'ankle'],
  ['muscleTear', 'kneeLigament', 'shoulder'],
  ['meniscus', 'fracture', 'achilles'],
  ['acl', 'brokenLeg'],
];

/// Draws an injury: band (weighted, shifted toward serious when
/// [fromFoul]), then days uniformly inside the band, then the type.
InjuryStub rollInjury(Rng rng, {required bool fromFoul}) {
  final band = rng.weightedIndex(
    fromFoul
        ? EngineTuning.injuryBandWeightsFoul
        : EngineTuning.injuryBandWeights,
  );
  final (lo, hi) = EngineTuning.injuryBandDays[band];
  final days = lo + rng.nextInt(hi - lo + 1);
  return InjuryStub(daysLeft: days, type: rng.pick(injuryTypes[band]));
}
