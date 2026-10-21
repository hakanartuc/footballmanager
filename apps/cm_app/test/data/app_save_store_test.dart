import 'dart:io';
import 'dart:typed_data';

import 'package:cm_app/data/app_save_store.dart';
import 'package:engine/engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('cm_saves_'));
  tearDown(() => temp.deleteSync(recursive: true));

  test('open(root:) creates the directory and round-trips a write', () async {
    final root = Directory('${temp.path}${Platform.pathSeparator}saves');
    final store = await AppSaveStore.open(root: root);
    expect(store, isA<FileSaveStore>());
    expect(root.existsSync(), isTrue);

    final bytes = Uint8List.fromList([1, 2, 3]);
    final meta = SlotInfo(
      slot: 1,
      managerName: 'Test Manager',
      clubName: null,
      date: GameDate(10),
      seasonYear: 2026,
      savedAt: DateTime(2026, 1, 1),
      bytes: bytes.length,
    );
    await store.write(1, bytes, meta);
    expect(await store.read(1), bytes);
    expect((await store.list()).single.managerName, 'Test Manager');
  });
}
