import 'package:engine/engine.dart';
import 'package:test/test.dart';

import 'match_helpers.dart';

/// Home through ball (see possession_test): owner home, centre lane,
/// shooter 2, assister 3, then [outcome] and the trailing [tail] draws.
List<double> homeThroughBall(double outcome, [List<double> tail = const []]) =>
    [0.0, 0.5, 0.5, 0.0, 0.0, 0.0, 0.0, outcome, ...tail];

/// Foul by away player 101 on home player 1 with [card]; no set piece, no
/// injury (see side_effects_test).
List<double> foul(double card) => [0.0, 0.0, 0.0, card, 0.5, 0.99, 0.99];

/// As [foul] with a straight red: the reason draw (normal) follows the card.
const redFoul = [0.0, 0.0, 0.0, 0.001, 0.5, 0.5, 0.99, 0.99];

PossessionStep homeStep() => PossessionStep(
  minute: 1,
  half: 1,
  attackingId: 1,
  lane: Lane.centre,
  counter: false,
  seconds: 60,
);

/// [uniformWorld] plus home bench players 13 (dc), 14 (mc), 15 (st).
World benchWorld() {
  final w = uniformWorld();
  w.players[13] = uniformPlayer(13, Position.dc);
  w.players[14] = uniformPlayer(14, Position.mc);
  w.players[15] = uniformPlayer(15, Position.st);
  return w;
}

/// A 90-minute match with a home bench; ratings untouched.
MatchState fullMatch(World w) =>
    startMatch(w, homeBench: const [13, 14, 15])..minute = 90;

void sub(MatchState s, World w, int minute, PlayerId out, PlayerId inId) {
  s.minute = minute;
  applyCommand(s, w, MatchRules.league, Substitute(1, outId: out, inId: inId));
}

double rating(MatchState s, PlayerId id) => s.ratings[id]!.value;

Goal goal(PlayerId scorer, {bool own = false}) => Goal(
  minute: 10,
  half: 1,
  clubId: own ? 2 : 1,
  scorerId: scorer,
  assistId: null,
  type: ChanceType.throughBall,
  isPenalty: false,
  isOwnGoal: own,
);

void main() {
  group('creditRating', () {
    test('each event carries the spec delta', () {
      expect(RatingEvent.goal.delta, 1.0);
      expect(RatingEvent.assist.delta, 0.5);
      expect(RatingEvent.save.delta, 0.1);
      expect(RatingEvent.possessionLost.delta, -0.05);
      expect(RatingEvent.criticalError.delta, -0.5);
      expect(RatingEvent.yellow.delta, -0.3);
      expect(RatingEvent.red.delta, -1.0);
    });

    test('a pinned sequence gives a pinned running value', () {
      final s = startMatch(uniformWorld());
      creditRating(s, 9, RatingEvent.goal);
      creditRating(s, 9, RatingEvent.assist);
      creditRating(s, 9, RatingEvent.yellow);
      for (var i = 0; i < 4; i++) {
        creditRating(s, 9, RatingEvent.possessionLost);
      }
      expect(rating(s, 9), closeTo(6.0 + 1.0 + 0.5 - 0.3 - 0.2, 1e-9));
      creditRating(s, 101, RatingEvent.save);
      creditRating(s, 101, RatingEvent.criticalError);
      expect(rating(s, 101), closeTo(5.6, 1e-9));
      expect(rating(s, 10), 6.0);
    });
  });

  group('finaliseRatings', () {
    test('pinned match: win, clean sheet, goals, rounding', () {
      final w = uniformWorld();
      final s = startMatch(w)..minute = 90;
      s.home.goals = 1;
      creditRating(s, 10, RatingEvent.goal);
      creditRating(s, 9, RatingEvent.assist);
      for (var i = 0; i < 3; i++) {
        creditRating(s, 101, RatingEvent.save);
      }
      finaliseRatings(s);
      expect(s.ratings.length, 22);
      expect(rating(s, 10), 7.3);
      expect(rating(s, 9), 6.8);
      expect(rating(s, 1), 6.8);
      expect(rating(s, 2), 6.8);
      expect(rating(s, 5), 6.8);
      expect(rating(s, 6), 6.3);
      expect(rating(s, 101), 6.3);
      expect(rating(s, 102), 6.0);
      expect(rating(s, 111), 6.0);
    });

    test('clamps to 1..10', () {
      final s = startMatch(uniformWorld())..minute = 90;
      s.away.goals = 1;
      for (var i = 0; i < 6; i++) {
        creditRating(s, 10, RatingEvent.goal);
        creditRating(s, 7, RatingEvent.red);
      }
      finaliseRatings(s);
      expect(rating(s, 10), 10.0);
      expect(rating(s, 7), 1.0);
    });

    test('clean sheet: only keeper and defence slots, only at 0 conceded', () {
      final w = benchWorld();
      final s = fullMatch(w);
      // A defender off for a defender, a midfielder into a defence slot.
      sub(s, w, 60, 3, 13);
      sub(s, w, 70, 4, 14);
      s.minute = 90;
      finaliseRatings(s);
      for (final id in [1, 2, 3, 4, 5, 13, 14, 101, 102, 105]) {
        expect(rating(s, id), 6.5, reason: 'id $id');
      }
      for (final id in [6, 9, 11, 106, 111]) {
        expect(rating(s, id), 6.0, reason: 'id $id');
      }

      final t = fullMatch(w);
      t.home.goals = 1;
      t.away.goals = 1;
      finaliseRatings(t);
      expect(rating(t, 1), 6.0);
      expect(rating(t, 2), 6.0);
      expect(rating(t, 101), 6.0);
    });

    test('win bonus reaches substituted, sent-off and injured players', () {
      final w = benchWorld();
      final s = fullMatch(w);
      s.home.goals = 2;
      s.away.goals = 1;
      sub(s, w, 60, 10, 15);
      s.events.add(
        Booking(
          minute: 50,
          half: 2,
          clubId: 1,
          playerId: 9,
          kind: CardKind.red,
          reason: FoulKind.normal,
        ),
      );
      s.home.sentOff.add(9);
      s.home.removeFromPitch(9);
      s.events.add(
        Injury(
          minute: 40,
          half: 1,
          clubId: 1,
          playerId: 8,
          injury: InjuryStub(daysLeft: 3, type: 'knock'),
        ),
      );
      s.home.injuredOff.add(8);
      s.home.removeFromPitch(8);
      s.minute = 90;
      finaliseRatings(s);
      for (final id in [6, 8, 9, 10, 15]) {
        expect(rating(s, id), 6.3, reason: 'id $id');
      }
      expect(rating(s, 106), 6.0);
    });

    test('fewer than 10 minutes: no rating', () {
      final w = benchWorld();
      final s = fullMatch(w);
      sub(s, w, 80, 9, 15);
      sub(s, w, 81, 10, 14);
      s.events.add(
        Booking(
          minute: 9,
          half: 1,
          clubId: 2,
          playerId: 107,
          kind: CardKind.secondYellow,
          reason: FoulKind.normal,
        ),
      );
      s.away.sentOff.add(107);
      s.away.removeFromPitch(107);
      s.events.add(
        Injury(
          minute: 5,
          half: 1,
          clubId: 2,
          playerId: 108,
          injury: InjuryStub(daysLeft: 3, type: 'knock'),
        ),
      );
      s.away.injuredOff.add(108);
      s.away.removeFromPitch(108);
      s.minute = 90;
      finaliseRatings(s);
      expect(s.ratings.containsKey(15), isTrue);
      expect(s.ratings.containsKey(14), isFalse);
      expect(s.ratings.containsKey(107), isFalse);
      expect(s.ratings.containsKey(108), isFalse);
      expect(s.ratings.containsKey(9), isTrue);
      expect(s.ratings.containsKey(10), isTrue);
      expect(s.ratings.length, 21);
    });

    test('is idempotent', () {
      final s = startMatch(uniformWorld())..minute = 90;
      s.home.goals = 1;
      creditRating(s, 10, RatingEvent.goal);
      finaliseRatings(s);
      final first = {for (final e in s.ratings.entries) e.key: e.value.value};
      finaliseRatings(s);
      expect({for (final e in s.ratings.entries) e.key: e.value.value}, first);
      expect(rating(s, 10), 7.3);
    });
  });

  group('manOfTheMatch', () {
    test('highest rating, then more goals, then lower id', () {
      final s = startMatch(uniformWorld())..minute = 90;
      finaliseRatings(s);
      s.ratings[9]!.value = 8.0;
      s.ratings[7]!.value = 8.0;
      s.ratings[105]!.value = 7.9;
      expect(manOfTheMatch(s), 7);

      s.events.add(goal(9));
      expect(manOfTheMatch(s), 9);

      s.events.add(goal(7, own: true));
      expect(manOfTheMatch(s), 9);

      s.ratings[105]!.value = 8.1;
      expect(manOfTheMatch(s), 105);
    });
  });

  group('wired producers', () {
    test('a goal credits the scorer +1.0 and the assister +0.5', () {
      final w = uniformWorld();
      final s = startMatch(w);
      resolvePossession(s, w, ScriptedRng(homeThroughBall(0.1)), detail: false);
      expect(rating(s, 2), closeTo(7.0, 1e-9));
      expect(rating(s, 3), closeTo(6.5, 1e-9));
      expect(rating(s, 101), 6.0);
    });

    test('a save credits the defending keeper +0.1', () {
      final w = uniformWorld();
      final s = startMatch(w);
      resolvePossession(
        s,
        w,
        ScriptedRng(homeThroughBall(0.4, [0.99, 0.99])),
        detail: false,
      );
      expect(rating(s, 101), closeTo(6.1, 1e-9));
      expect(rating(s, 2), 6.0);
    });

    test('a keeper-error goal is a critical error for the keeper', () {
      final w = uniformWorld();
      final s = startMatch(
        w,
        cond: const MatchConditions(
          weather: Weather.rainy,
          pitch: 8,
          attendance: 1,
          homeAdvantage: 1.0,
        ),
      );
      resolvePossession(
        s,
        w,
        ScriptedRng(homeThroughBall(0.34)),
        detail: false,
      );
      expect(rating(s, 2), closeTo(7.0, 1e-9));
      expect(rating(s, 101), closeTo(5.5, 1e-9));

      // A goal inside xG is not the keeper's error.
      final t = startMatch(w, cond: s.conditions);
      resolvePossession(t, w, ScriptedRng(homeThroughBall(0.1)), detail: false);
      expect(rating(t, 101), 6.0);
    });

    test('a yellow −0.3, a red −1.0, a second yellow −1.0', () {
      final w = uniformWorld();
      final s = startMatch(w);
      applySideEffects(s, homeStep(), w, ScriptedRng(foul(0.05)));
      expect(rating(s, 101), closeTo(5.7, 1e-9));

      final t = startMatch(w);
      applySideEffects(t, homeStep(), w, ScriptedRng(redFoul));
      expect(rating(t, 101), closeTo(5.0, 1e-9));

      final u = startMatch(w);
      u.away.yellows[101] = 1;
      applySideEffects(u, homeStep(), w, ScriptedRng(foul(0.05)));
      expect(rating(u, 101), closeTo(5.0, 1e-9));
    });
  });
}
