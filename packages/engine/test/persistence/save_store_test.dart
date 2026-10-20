import 'dart:io';
import 'dart:typed_data';

import 'package:engine/engine.dart';
import 'package:test/test.dart';

TypeMatcher<SaveError> _saveError(SaveErrorKind kind) =>
    isA<SaveError>().having((e) => e.kind, 'kind', kind);

SlotInfo _meta(int slot, {String manager = 'Test Manager', int bytes = 3}) =>
    SlotInfo(
      slot: slot,
      managerName: manager,
      clubName: slot.isEven ? 'Club $slot' : null,
      date: GameDate.ymd(2026, 7, slot),
      seasonYear: 2026,
      savedAt: DateTime.utc(2026, 10, 20, 12, slot),
      bytes: bytes,
    );

Uint8List _bytes(List<int> b) => Uint8List.fromList(b);

/// The behaviour every [SaveStore] must share.
void runSaveStoreContract(SaveStore Function() make) {
  late SaveStore store;
  setUp(() => store = make());

  test('a new store lists no slots', () async {
    expect(await store.list(), isEmpty);
  });

  test('write then read returns the bytes and list returns the meta', () async {
    await store.write(2, _bytes([1, 2, 3]), _meta(2));
    expect(await store.read(2), [1, 2, 3]);
    final listed = await store.list();
    expect(listed.map((s) => s.toJson()), [_meta(2).toJson()]);
  });

  test('list is sorted by slot', () async {
    for (final slot in [5, 1, 3]) {
      await store.write(slot, _bytes([slot]), _meta(slot));
    }
    expect((await store.list()).map((s) => s.slot), [1, 3, 5]);
  });

  test('read of an empty slot throws SaveError(missingSlot)', () async {
    await store.write(1, _bytes([1]), _meta(1));
    await expectLater(
      store.read(4),
      throwsA(_saveError(SaveErrorKind.missingSlot)),
    );
  });

  test('overwrite replaces bytes and meta', () async {
    await store.write(1, _bytes([1, 1, 1, 1]), _meta(1, bytes: 4));
    await store.write(1, _bytes([9]), _meta(1, manager: 'New', bytes: 1));
    expect(await store.read(1), [9]);
    final listed = await store.list();
    expect(listed, hasLength(1));
    expect(listed.single.managerName, 'New');
    expect(listed.single.bytes, 1);
  });

  test('delete removes the slot; deleting an empty slot is a no-op', () async {
    await store.write(1, _bytes([1]), _meta(1));
    await store.write(2, _bytes([2]), _meta(2));
    await store.delete(1);
    await store.delete(3);
    expect((await store.list()).map((s) => s.slot), [2]);
    await expectLater(
      store.read(1),
      throwsA(_saveError(SaveErrorKind.missingSlot)),
    );
    expect(await store.read(2), [2]);
  });

  test('later changes to the written buffer do not affect the store', () async {
    final buf = _bytes([1, 2]);
    await store.write(1, buf, _meta(1));
    buf[0] = 99;
    expect(await store.read(1), [1, 2]);
  });

  test('rejects a non-positive slot or a meta for another slot', () async {
    expect(() => store.write(0, _bytes([1]), _meta(0)), throwsArgumentError);
    expect(() => store.write(1, _bytes([1]), _meta(2)), throwsArgumentError);
  });

  test('stores a real encoded world', () async {
    final w = createNewGame(
      NewGameSpec(
        seed: 3,
        size: WorldSize.small,
        managerFirstName: 'Ada',
        managerLastName: 'Lovelace',
        managerCountryCode: 'TR',
        startClubId: null,
      ),
    );
    const codec = JsonGzipSaveCodec();
    final bytes = codec.encode(w);
    await store.write(
      1,
      bytes,
      SlotInfo.fromWorld(
        1,
        w,
        savedAt: DateTime.utc(2026),
        bytes: bytes.length,
      ),
    );
    expect(codec.encode(codec.decode(await store.read(1))), bytes);
    expect((await store.list()).single.bytes, bytes.length);
  });
}

void main() {
  group('MemorySaveStore', () => runSaveStoreContract(MemorySaveStore.new));

  group('FileSaveStore', () {
    late Directory root;
    setUp(() => root = Directory.systemTemp.createTempSync('engine_saves_'));
    tearDown(() => root.deleteSync(recursive: true));

    runSaveStoreContract(() => FileSaveStore(root));

    test('lays out slot_<n>/world.bin and meta.json', () async {
      await FileSaveStore(root).write(3, _bytes([7]), _meta(3));
      expect(File('${root.path}/slot_3/world.bin').readAsBytesSync(), [7]);
      expect(File('${root.path}/slot_3/meta.json').existsSync(), isTrue);
      expect(
        root.listSync(recursive: true).map((e) => e.path.split('/').last),
        unorderedEquals(['slot_3', 'world.bin', 'meta.json']),
      );
    });

    test(
      'list ignores directories without meta.json and other entries',
      () async {
        final store = FileSaveStore(root);
        await store.write(2, _bytes([2]), _meta(2));
        Directory('${root.path}/slot_4').createSync();
        Directory('${root.path}/other').createSync();
        File('${root.path}/slot_5').writeAsStringSync('');
        expect((await store.list()).map((s) => s.slot), [2]);
      },
    );

    test('list of a missing root is empty', () async {
      final store = FileSaveStore(Directory('${root.path}/absent'));
      expect(await store.list(), isEmpty);
    });

    test('IO failures throw SaveError(io)', () async {
      final notADir = File('${root.path}/file')..writeAsStringSync('x');
      final store = FileSaveStore(Directory(notADir.path));
      await expectLater(
        store.write(1, _bytes([1]), _meta(1)),
        throwsA(_saveError(SaveErrorKind.io)),
      );
    });
  });

  group('SlotInfo', () {
    test('JSON round trip', () {
      final m = _meta(2);
      expect(SlotInfo.fromJson(m.toJson()).toJson(), m.toJson());
      expect(m.toJson()['savedAt'], '2026-10-20T12:02:00.000Z');
    });

    test('fromWorld reflects the user manager, club and date', () {
      final w = createNewGame(
        NewGameSpec(
          seed: 1,
          size: WorldSize.small,
          managerFirstName: 'Ada',
          managerLastName: 'Lovelace',
          managerCountryCode: 'TR',
          startClubId: null,
        ),
      );
      final savedAt = DateTime.utc(2026, 10, 20);
      final unemployed = SlotInfo.fromWorld(2, w, savedAt: savedAt, bytes: 10);
      expect(unemployed.slot, 2);
      expect(unemployed.managerName, 'Ada Lovelace');
      expect(unemployed.clubName, isNull);
      expect(unemployed.date, w.date);
      expect(unemployed.seasonYear, w.seasonYear);
      expect(unemployed.savedAt, savedAt);
      expect(unemployed.bytes, 10);

      final club = w.clubs.values.first;
      w.managers[w.userManagerId]!.clubId = club.id;
      final employed = SlotInfo.fromWorld(1, w, savedAt: savedAt, bytes: 10);
      expect(employed.clubName, club.name);
    });
  });
}
