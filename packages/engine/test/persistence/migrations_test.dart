import 'package:engine/engine.dart';
import 'package:test/test.dart';

TypeMatcher<SaveError> _saveError(SaveErrorKind kind) =>
    isA<SaveError>().having((e) => e.kind, 'kind', kind);

Map<String, dynamic> _renameOldToNew(Map<String, dynamic> env) {
  final w = env['world'] as Map<String, dynamic>;
  w['new'] = w.remove('old');
  return env;
}

Map<String, dynamic> _identity(Map<String, dynamic> env) => env;

void main() {
  test('schema v3 registers the 1 -> 2 and 2 -> 3 steps', () {
    expect(currentSchemaVersion, 3);
    expect(migrations.map((m) => m.from), [1, 2]);
  });

  group('1 -> 2', () {
    Map<String, dynamic> entry(int day) => {
      'date': day,
      'event': {'type': 'SeasonEnded', 'date': day, 'seasonYear': 2026},
      'read': day.isEven,
    };

    test('gives inbox entries ids 1..n in stored order and sets ids.inbox', () {
      final env = <String, dynamic>{
        'schemaVersion': 1,
        'world': <String, dynamic>{
          'inbox': [entry(1), entry(2), entry(3)],
          'ids': <String, dynamic>{'player': 40},
          'clubs': <String, dynamic>{},
        },
      };
      final out = migrate(env);
      expect(out['schemaVersion'], currentSchemaVersion);
      final w = out['world'] as Map<String, dynamic>;
      final inbox = w['inbox'] as List;
      expect([
        for (final m in inbox) (m as Map).keys.toList(),
      ], everyElement(['id', 'date', 'event', 'read']));
      expect([for (final m in inbox) (m as Map)['id']], [1, 2, 3]);
      expect([for (final m in inbox) (m as Map)['read']], [false, true, false]);
      expect(w['ids'], {'player': 40, 'inbox': 3});
    });

    test('creates ids when it is missing', () {
      final out = migrate({
        'schemaVersion': 1,
        'world': <String, dynamic>{
          'inbox': <Object?>[],
          'clubs': <String, dynamic>{},
        },
      });
      expect((out['world'] as Map)['ids'], {'inbox': 0});
    });
  });

  group('2 -> 3', () {
    /// A v2 envelope built from a current world by downgrading every club:
    /// `tactics`/`activeTactic` removed, `formation` restored.
    Map<String, dynamic> v2Envelope() {
      final world = worldToJson(
        createNewGame(
          NewGameSpec(
            seed: 5,
            size: WorldSize.small,
            managerFirstName: 'A',
            managerLastName: 'B',
            managerCountryCode: 'TR',
            startClubId: null,
          ),
        ),
      );
      final clubs = world['clubs'] as Map<String, dynamic>;
      for (final c in clubs.values) {
        final club = c as Map<String, dynamic>;
        club.remove('tactics');
        club.remove('activeTactic');
        club['formation'] = Formation.values[(club['id'] as int) % 6].name;
      }
      world['schemaVersion'] = 2;
      return {'schemaVersion': 2, 'world': world};
    }

    test('gives every club three preset tactics with the first active', () {
      final env = v2Envelope();
      final before = {
        for (final c in (env['world'] as Map)['clubs'].values)
          c['id'] as int: c['formation'] as String,
      };
      final out = migrate(env);
      expect(out['schemaVersion'], 3);
      final clubs = (out['world'] as Map)['clubs'] as Map<String, dynamic>;
      expect(clubs, isNotEmpty);
      for (final c in clubs.values) {
        final club = c as Map<String, dynamic>;
        expect(club.containsKey('formation'), isFalse);
        expect(club['activeTactic'], 0);
        final tactics = club['tactics'] as List;
        expect(tactics, hasLength(3));
        expect([for (final t in tactics) (t as Map)['name']], ['1', '2', '3']);
        expect(
          [for (final t in tactics) (t as Map)['formation']],
          [before[club['id'] as int], 'f433', 'f532'],
        );
      }
    });

    test('the migrated envelope decodes with the migrated formations', () {
      final env = v2Envelope();
      final before = {
        for (final c in (env['world'] as Map)['clubs'].values)
          c['id'] as int: Formation.values.byName(c['formation'] as String),
      };
      final w = worldFromJson(migrate(env)['world'] as Map<String, dynamic>);
      for (final c in w.clubs.values) {
        expect(c.formation, before[c.id]);
        expect(c.tactic.slots, formationSlots(before[c.id]!));
        expect(c.tactics[1].slots, formationSlots(Formation.f433));
        expect(c.tactics[2].slots, formationSlots(Formation.f532));
        expect(c.tactic.mentality, Mentality.balanced);
      }
    });
  });

  test('a current envelope is returned unchanged', () {
    final env = {
      'schemaVersion': currentSchemaVersion,
      'world': {'old': 1},
    };
    expect(migrate(env), {
      'schemaVersion': currentSchemaVersion,
      'world': {'old': 1},
    });
  });

  test('a registered 0 -> 1 migration renames a key and bumps the version', () {
    final env = <String, dynamic>{
      'schemaVersion': 0,
      'world': <String, dynamic>{'old': 7, 'keep': true},
    };
    final out = migrate(
      env,
      registry: const [
        Migration(from: 0, apply: _renameOldToNew),
        Migration(from: 1, apply: _identity),
        Migration(from: 2, apply: _identity),
      ],
    );
    expect(out, {
      'schemaVersion': currentSchemaVersion,
      'world': {'new': 7, 'keep': true},
    });
  });

  test('migrations are chained in order', () {
    final applied = <int>[];
    Migration step(int from) => Migration(
      from: from,
      apply: (env) {
        applied.add(from);
        return env;
      },
    );
    // Registered out of order on purpose: lookup is by `from`.
    final out = migrate(
      {'schemaVersion': -1, 'world': <String, dynamic>{}},
      registry: [step(2), step(1), step(0), step(-1)],
    );
    expect(applied, [-1, 0, 1, 2]);
    expect(out['schemaVersion'], currentSchemaVersion);
  });

  test('a newer envelope throws SaveError(newerSchema)', () {
    expect(
      () => migrate({'schemaVersion': 99, 'world': <String, dynamic>{}}),
      throwsA(_saveError(SaveErrorKind.newerSchema)),
    );
  });

  test('a gap in the registry throws SaveError(corrupt)', () {
    expect(
      () => migrate({'schemaVersion': 0, 'world': <String, dynamic>{}}),
      throwsA(
        _saveError(
          SaveErrorKind.corrupt,
        ).having((e) => e.message, 'message', 'no migration from v0'),
      ),
    );
  });
}
