import 'package:cm_app/data/entitlements.dart';
import 'package:cm_app/data/game_repository.dart';
import 'package:cm_app/engine/in_process_gateway.dart';
import 'package:engine/engine.dart';
import 'package:flutter_test/flutter_test.dart';

NewGameSpec _spec() => NewGameSpec(
  seed: 1,
  size: WorldSize.small,
  managerFirstName: 'Test',
  managerLastName: 'Manager',
  managerCountryCode: 'TR',
  startClubId: null,
);

void main() {
  late InProcessGateway gateway;
  late MemorySaveStore store;
  late GameRepository repo;
  late DateTime clock;

  setUp(() {
    gateway = InProcessGateway();
    store = MemorySaveStore();
    clock = DateTime(2026, 1, 1);
    repo = GameRepository(
      gateway,
      store,
      now: () => clock = clock.add(const Duration(minutes: 1)),
    );
  });

  tearDown(() => gateway.dispose());

  Future<void> advanceDay() => gateway.advanceToNext(maxDays: 1);

  test('newGame writes one autosave to slot 6', () async {
    await repo.newGame(_spec());
    final slots = await store.list();
    expect(slots.map((s) => s.slot), [6]);
    final home = await gateway.home();
    final info = slots.single;
    expect(info.date, home.date);
    expect(info.seasonYear, home.seasonYear);
    expect(info.managerName, home.managerName);
    expect(info.clubName, isNull);
    expect(info.bytes, (await store.read(6)).length);
  });

  test('autosaves fill 6, 7, 8 then overwrite the oldest', () async {
    await repo.newGame(_spec()); // slot 6
    final dates = [(await gateway.home()).date];
    for (var i = 0; i < 2; i++) {
      await advanceDay();
      await repo.autosave();
      dates.add((await gateway.home()).date);
    }
    var slots = await store.list();
    expect(slots.map((s) => s.slot), [6, 7, 8]);
    expect(slots.map((s) => s.date), dates);

    await advanceDay();
    await repo.autosave();
    final date4 = (await gateway.home()).date;
    slots = await store.list();
    expect(slots.map((s) => s.slot), [6, 7, 8]);
    expect(slots.firstWhere((s) => s.slot == 6).date, date4);
    expect(slots.firstWhere((s) => s.slot == 7).date, dates[1]);
    expect(slots.firstWhere((s) => s.slot == 8).date, dates[2]);

    final newest = await repo.newestAutosave();
    expect(newest!.slot, 6);
    expect(newest.date, date4);

    // Slot 7 is now the oldest, though not the lowest.
    await advanceDay();
    await repo.autosave();
    final date5 = (await gateway.home()).date;
    slots = await store.list();
    expect(slots.firstWhere((s) => s.slot == 6).date, date4);
    expect(slots.firstWhere((s) => s.slot == 7).date, date5);
    expect(slots.firstWhere((s) => s.slot == 8).date, dates[2]);
    expect((await repo.newestAutosave())!.slot, 7);
  });

  test('autosaves lists the occupied autosave slots newest first', () async {
    await repo.newGame(_spec()); // slot 6
    await advanceDay();
    await repo.autosave(); // slot 7
    await repo.saveToSlot(1);
    expect((await repo.autosaves()).map((s) => s.slot), [7, 6]);
  });

  test('newestAutosave is null on an empty store', () async {
    expect(await repo.newestAutosave(), isNull);
  });

  test('saveToSlot then loadSlot restores the date', () async {
    await repo.newGame(_spec());
    final saved = (await gateway.home()).date;
    await repo.saveToSlot(2);
    await advanceDay();
    expect((await gateway.home()).date, isNot(saved));

    await repo.loadSlot(2);
    expect((await gateway.home()).date, saved);
    final manual = await repo.manualSlots();
    expect(manual.map((s) => s.slot), [2]);
    expect(manual.single.date, saved);
  });

  test('loadSlot of an empty slot throws SaveError(missingSlot)', () async {
    await repo.newGame(_spec());
    expect(
      repo.loadSlot(3),
      throwsA(
        isA<SaveError>().having(
          (e) => e.kind,
          'kind',
          SaveErrorKind.missingSlot,
        ),
      ),
    );
  });

  test('saveToSlot outside manual slots throws ArgumentError', () async {
    await repo.newGame(_spec());
    expect(repo.saveToSlot(7), throwsArgumentError);
  });

  test('deleteSlot empties a manual slot', () async {
    await repo.newGame(_spec());
    await repo.saveToSlot(1);
    await repo.deleteSlot(1);
    expect(await repo.manualSlots(), isEmpty);
  });

  test('continueLast is false on an empty store', () async {
    expect(await repo.continueLast(), isFalse);
  });

  test('continueLast loads the newest autosave', () async {
    await repo.newGame(_spec());
    final saved = (await gateway.home()).date;
    final fresh = InProcessGateway();
    addTearDown(fresh.dispose);
    final other = GameRepository(fresh, store);
    expect(await other.continueLast(), isTrue);
    expect((await fresh.home()).date, saved);
  });

  test('Entitlements.dev allows every size; maxWorldSize is the largest', () {
    for (final s in WorldSize.values) {
      expect(Entitlements.dev.allows(s), isTrue);
    }
    expect(Entitlements.dev.maxWorldSize, WorldSize.large);
    const small = Entitlements(allowedSizes: {WorldSize.small});
    expect(small.allows(WorldSize.medium), isFalse);
    expect(small.maxWorldSize, WorldSize.small);
  });
}
