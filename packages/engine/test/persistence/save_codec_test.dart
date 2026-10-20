import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:engine/engine.dart';
import 'package:test/test.dart';

World _world() => createNewGame(
  NewGameSpec(
    seed: 1,
    size: WorldSize.small,
    managerFirstName: 'Test',
    managerLastName: 'Manager',
    managerCountryCode: 'TR',
    startClubId: null,
  ),
);

Uint8List _gzipJson(Object? value) =>
    GZipEncoder().encodeBytes(utf8.encode(jsonEncode(value)), level: 6);

TypeMatcher<SaveError> _saveError(SaveErrorKind kind) =>
    isA<SaveError>().having((e) => e.kind, 'kind', kind);

void main() {
  const codec = JsonGzipSaveCodec();
  late World world;
  late Uint8List bytes;

  setUpAll(() {
    world = _world();
    bytes = codec.encode(world);
  });

  test('encode is deterministic', () {
    expect(codec.encode(world), bytes);
  });

  test('encode -> decode -> encode gives identical bytes', () {
    expect(codec.encode(codec.decode(bytes)), bytes);
  });

  test('decoded world equals the original as JSON', () {
    final decoded = codec.decode(bytes);
    expect(jsonEncode(worldToJson(decoded)), jsonEncode(worldToJson(world)));
    expect(decoded.schemaVersion, currentSchemaVersion);
    expect(decoded.squadOf(world.clubs.keys.first), isNotEmpty);
  });

  test('bytes are a gzipped envelope with schemaVersion and world', () {
    final envelope =
        jsonDecode(utf8.decode(GZipDecoder().decodeBytes(bytes)))
            as Map<String, dynamic>;
    expect(envelope.keys, ['schemaVersion', 'world']);
    expect(envelope['schemaVersion'], currentSchemaVersion);
  });

  group('corrupt input throws SaveError(corrupt)', () {
    final random = Random(42);
    final cases = <String, Uint8List Function()>{
      'random bytes': () =>
          Uint8List.fromList(List.generate(512, (_) => random.nextInt(256))),
      'empty bytes': () => Uint8List(0),
      'truncated save': () =>
          Uint8List.sublistView(bytes, 0, bytes.length ~/ 2),
      'gzip of non-utf8': () =>
          GZipEncoder().encodeBytes([0xff, 0xfe, 0xfd], level: 6),
      'gzip of non-JSON text': () =>
          GZipEncoder().encodeBytes(utf8.encode('not json'), level: 6),
      'envelope is a list': () => _gzipJson([1, 2]),
      'schemaVersion missing': () => _gzipJson({'world': <String, dynamic>{}}),
      'schemaVersion not an int': () =>
          _gzipJson({'schemaVersion': '1', 'world': <String, dynamic>{}}),
      'world missing': () => _gzipJson({'schemaVersion': 1}),
      'world not a map': () => _gzipJson({'schemaVersion': 1, 'world': 7}),
      'world map is malformed': () =>
          _gzipJson({'schemaVersion': 1, 'world': <String, dynamic>{}}),
      'world field has wrong type': () {
        final j = worldToJson(world)..['seed'] = 'x';
        return _gzipJson({'schemaVersion': 1, 'world': j});
      },
      'older schema without migration': () =>
          _gzipJson({'schemaVersion': 0, 'world': worldToJson(world)}),
    };
    for (final MapEntry(:key, :value) in cases.entries) {
      test(key, () {
        expect(
          () => codec.decode(value()),
          throwsA(_saveError(SaveErrorKind.corrupt)),
        );
      });
    }
  });

  test('newer schema throws SaveError(newerSchema)', () {
    final newer = _gzipJson({'schemaVersion': 99, 'world': worldToJson(world)});
    expect(
      () => codec.decode(newer),
      throwsA(_saveError(SaveErrorKind.newerSchema)),
    );
  });

  test('decode applies an injected migration before worldFromJson', () {
    final v0World = worldToJson(world);
    v0World['oldSeed'] = v0World.remove('seed');
    v0World['schemaVersion'] = 0;
    final v0 = _gzipJson({'schemaVersion': 0, 'world': v0World});
    final migrating = JsonGzipSaveCodec(
      migrations: [
        Migration(
          from: 0,
          apply: (env) {
            final w = env['world'] as Map<String, dynamic>;
            w['seed'] = w.remove('oldSeed');
            return env;
          },
        ),
      ],
    );

    final decoded = migrating.decode(v0);
    expect(decoded.seed, world.seed);
    expect(decoded.schemaVersion, currentSchemaVersion);
    expect(migrating.encode(decoded), bytes);
  });

  test('SaveError toString names the kind and message', () {
    final e = SaveError(SaveErrorKind.io, 'disk full');
    expect(e.toString(), 'SaveError(io): disk full');
  });
}
