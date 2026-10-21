import 'package:engine/engine.dart';

import '../engine/engine_gateway.dart';

const manualSlots = [1, 2, 3, 4, 5];
const autosaveSlots = [6, 7, 8];

/// Starts, saves and loads games: the engine gateway plus a [SaveStore].
class GameRepository {
  GameRepository(this.gateway, this.store, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final EngineGateway gateway;
  final SaveStore store;

  /// Wall clock for [SlotInfo.savedAt]; metadata only.
  final DateTime Function() _now;

  /// Starts a new game and autosaves it.
  Future<void> newGame(NewGameSpec spec) async {
    await gateway.newGame(spec);
    await autosave();
  }

  /// The occupied manual slots.
  Future<List<SlotInfo>> manualSlots() async => [
    for (final s in await store.list())
      if (_isManual(s.slot)) s,
  ];

  /// The occupied autosave slot saved last, or null.
  Future<SlotInfo?> newestAutosave() async {
    SlotInfo? newest;
    for (final s in await _autosaves()) {
      if (newest == null || s.savedAt.isAfter(newest.savedAt)) newest = s;
    }
    return newest;
  }

  /// Saves the game to manual [slot].
  Future<void> saveToSlot(int slot) async {
    if (!_isManual(slot)) {
      throw ArgumentError.value(slot, 'slot', 'not a manual slot');
    }
    await _saveTo(slot);
  }

  /// Loads [slot]. A [SaveError] from the store and a [GatewayError] from
  /// the gateway propagate.
  Future<void> loadSlot(int slot) async => gateway.load(await store.read(slot));

  Future<void> deleteSlot(int slot) => store.delete(slot);

  /// Saves to the first empty autosave slot, else the one saved longest ago.
  Future<void> autosave() async {
    final used = {for (final s in await _autosaves()) s.slot: s};
    var target = autosaveSlots.firstWhere(
      (s) => !used.containsKey(s),
      orElse: () => -1,
    );
    if (target == -1) {
      target = used.values
          .reduce((a, b) => b.savedAt.isBefore(a.savedAt) ? b : a)
          .slot;
    }
    await _saveTo(target);
  }

  /// Loads the newest autosave; false when there is none.
  Future<bool> continueLast() async {
    final newest = await newestAutosave();
    if (newest == null) return false;
    await loadSlot(newest.slot);
    return true;
  }

  Future<void> _saveTo(int slot) async {
    final bytes = await gateway.save();
    await store.write(slot, bytes, await _describe(slot, bytes.length));
  }

  /// [SlotInfo] for the loaded game, built from [HomeSnapshot] since the
  /// world is not reachable from the UI isolate.
  Future<SlotInfo> _describe(int slot, int bytes) async {
    final home = await gateway.home();
    return SlotInfo(
      slot: slot,
      managerName: home.managerName,
      clubName: home.clubName,
      date: home.date,
      seasonYear: home.seasonYear,
      savedAt: _now(),
      bytes: bytes,
    );
  }

  Future<List<SlotInfo>> _autosaves() async => [
    for (final s in await store.list())
      if (autosaveSlots.contains(s.slot)) s,
  ];

  static bool _isManual(int slot) => _manual.contains(slot);
}

/// [manualSlots], reachable inside [GameRepository] where the method of the
/// same name shadows it.
const _manual = manualSlots;
