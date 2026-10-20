import 'enums.dart';

/// Visible 1..20 attributes, one value per [Attr].
class Attributes {
  final List<int> _values;

  Attributes.filled(int v)
    : _values = List.filled(Attr.values.length, _clamp(v));

  Attributes.fromList(List<int> values)
    : _values = [for (final v in values) _clamp(v)] {
    if (values.length != Attr.values.length) {
      throw ArgumentError.value(
        values.length,
        'values.length',
        'expected ${Attr.values.length}',
      );
    }
  }

  int operator [](Attr a) => _values[a.index];

  void set(Attr a, int v) => _values[a.index] = _clamp(v);

  List<int> toList() => List.of(_values);

  static int _clamp(int v) => v.clamp(1, 20);
}

/// Hidden 1..20 attributes.
class HiddenAttrs {
  int injuryProneness;
  int consistency;
  int bigMatches;
  int professionalism;

  HiddenAttrs({
    required this.injuryProneness,
    required this.consistency,
    required this.bigMatches,
    required this.professionalism,
  });
}

const Map<PositionGroup, Map<Attr, int>> _caWeights = {
  PositionGroup.gk: {
    Attr.reflexes: 3,
    Attr.handling: 2,
    Attr.oneOnOnes: 2,
    Attr.aerialAbility: 2,
    Attr.commandOfArea: 1,
    Attr.positioning: 1,
    Attr.concentration: 1,
    Attr.agility: 1,
  },
  PositionGroup.def: {
    Attr.tackling: 3,
    Attr.positioning: 3,
    Attr.heading: 2,
    Attr.strength: 2,
    Attr.concentration: 2,
    Attr.pace: 1,
    Attr.anticipation: 1,
    Attr.passing: 1,
  },
  PositionGroup.mid: {
    Attr.passing: 3,
    Attr.decisions: 2,
    Attr.teamwork: 2,
    Attr.workRate: 2,
    Attr.stamina: 2,
    Attr.firstTouch: 1,
    Attr.tackling: 1,
    Attr.longShots: 1,
    Attr.anticipation: 1,
  },
  PositionGroup.att: {
    Attr.finishing: 3,
    Attr.composure: 2,
    Attr.pace: 2,
    Attr.acceleration: 1,
    Attr.dribbling: 2,
    Attr.firstTouch: 1,
    Attr.heading: 1,
    Attr.anticipation: 2,
  },
};

/// The CA weight table of [g]; attributes absent from it do not count.
Map<Attr, int> caWeightsFor(PositionGroup g) => _caWeights[g]!;

/// Current ability (1..200): the weighted mean of [p]'s group attributes × 10.
int computeCa(Attributes a, Position p) {
  final weights = _caWeights[p.group]!;
  var weighted = 0;
  var total = 0;
  for (final MapEntry(key: attr, value: w) in weights.entries) {
    weighted += w * a[attr];
    total += w;
  }
  return (weighted / total * 10).round().clamp(1, 200);
}
