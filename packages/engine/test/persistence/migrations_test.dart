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
  test('schema v2 registers the single 1 -> 2 step', () {
    expect(currentSchemaVersion, 2);
    expect(migrations.map((m) => m.from), [1]);
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
        },
      };
      final out = migrate(env);
      expect(out['schemaVersion'], 2);
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
        'world': <String, dynamic>{'inbox': <Object?>[]},
      });
      expect((out['world'] as Map)['ids'], {'inbox': 0});
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
      registry: [step(1), step(0), step(-1)],
    );
    expect(applied, [-1, 0, 1]);
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
