import 'package:engine/engine.dart';
import 'package:test/test.dart';

TypeMatcher<SaveError> _saveError(SaveErrorKind kind) =>
    isA<SaveError>().having((e) => e.kind, 'kind', kind);

Map<String, dynamic> _renameOldToNew(Map<String, dynamic> env) {
  final w = env['world'] as Map<String, dynamic>;
  w['new'] = w.remove('old');
  return env;
}

void main() {
  test('the v1 registry is empty', () {
    expect(currentSchemaVersion, 1);
    expect(migrations, isEmpty);
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
      registry: const [Migration(from: 0, apply: _renameOldToNew)],
    );
    expect(out, {
      'schemaVersion': 1,
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
      registry: [step(0), step(-1)],
    );
    expect(applied, [-1, 0]);
    expect(out['schemaVersion'], 1);
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
