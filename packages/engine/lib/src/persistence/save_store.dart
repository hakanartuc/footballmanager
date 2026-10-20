import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../core/game_date.dart';
import '../model/world.dart';
import 'save_codec.dart';

/// What a save menu shows for a slot, stored beside the save bytes.
///
/// [savedAt] is wall-clock metadata only; it never enters the world and is
/// not part of determinism.
class SlotInfo {
  final int slot;
  final String managerName;
  final String? clubName;
  final GameDate date;
  final int seasonYear;
  final DateTime savedAt;
  final int bytes;

  const SlotInfo({
    required this.slot,
    required this.managerName,
    required this.clubName,
    required this.date,
    required this.seasonYear,
    required this.savedAt,
    required this.bytes,
  });

  /// The user manager, their club and the date of [w].
  factory SlotInfo.fromWorld(
    int slot,
    World w, {
    required DateTime savedAt,
    required int bytes,
  }) {
    final manager = w.managers[w.userManagerId]!;
    return SlotInfo(
      slot: slot,
      managerName: '${manager.firstName} ${manager.lastName}',
      clubName: w.userClub?.name,
      date: w.date,
      seasonYear: w.seasonYear,
      savedAt: savedAt,
      bytes: bytes,
    );
  }

  Map<String, dynamic> toJson() => {
    'slot': slot,
    'managerName': managerName,
    'clubName': clubName,
    'date': date.dayIndex,
    'seasonYear': seasonYear,
    'savedAt': savedAt.toIso8601String(),
    'bytes': bytes,
  };

  factory SlotInfo.fromJson(Map<String, dynamic> j) => SlotInfo(
    slot: j['slot'] as int,
    managerName: j['managerName'] as String,
    clubName: j['clubName'] as String?,
    date: GameDate(j['date'] as int),
    seasonYear: j['seasonYear'] as int,
    savedAt: DateTime.parse(j['savedAt'] as String),
    bytes: j['bytes'] as int,
  );
}

/// Numbered save slots. Slots are positive ints (the app uses 1..5).
abstract interface class SaveStore {
  /// Occupied slots, sorted by slot.
  Future<List<SlotInfo>> list();

  /// Stores [bytes] and [meta] in [slot], replacing what was there.
  Future<void> write(int slot, Uint8List bytes, SlotInfo meta);

  /// Throws [SaveError] `missingSlot` when [slot] is empty.
  Future<Uint8List> read(int slot);

  /// Empties [slot]; a no-op when it is already empty.
  Future<void> delete(int slot);
}

void _checkWrite(int slot, SlotInfo meta) {
  if (slot < 1) throw ArgumentError.value(slot, 'slot', 'must be positive');
  if (meta.slot != slot) {
    throw ArgumentError.value(meta.slot, 'meta.slot', 'must equal $slot');
  }
}

SaveError _missing(int slot) =>
    SaveError(SaveErrorKind.missingSlot, 'slot $slot is empty');

/// An in-memory [SaveStore] for tests.
class MemorySaveStore implements SaveStore {
  final Map<int, Uint8List> _bytes = {};
  final Map<int, SlotInfo> _meta = {};

  @override
  Future<List<SlotInfo>> list() async => [
    for (final k in _meta.keys.toList()..sort()) _meta[k]!,
  ];

  @override
  Future<void> write(int slot, Uint8List bytes, SlotInfo meta) async {
    _checkWrite(slot, meta);
    _bytes[slot] = Uint8List.fromList(bytes);
    _meta[slot] = meta;
  }

  @override
  Future<Uint8List> read(int slot) async {
    final bytes = _bytes[slot];
    if (bytes == null) throw _missing(slot);
    return Uint8List.fromList(bytes);
  }

  @override
  Future<void> delete(int slot) async {
    _bytes.remove(slot);
    _meta.remove(slot);
  }
}

/// A [SaveStore] on disk: `<root>/slot_<n>/world.bin` and
/// `<root>/slot_<n>/meta.json` (spec §18.3).
///
/// `world.bin` is written to a temp file and renamed into place. A slot is
/// listed only once its `meta.json` exists. IO failures throw [SaveError]
/// `io`.
class FileSaveStore implements SaveStore {
  final Directory root;

  FileSaveStore(this.root);

  static final _slotDir = RegExp(r'^slot_([1-9][0-9]*)$');

  Directory _dir(int slot) => Directory('${root.path}/slot_$slot');
  File _world(int slot) => File('${_dir(slot).path}/world.bin');
  File _metaFile(int slot) => File('${_dir(slot).path}/meta.json');

  @override
  Future<List<SlotInfo>> list() => _io(() async {
    if (!await root.exists()) return [];
    final slots = <int>[];
    await for (final e in root.list(followLinks: false)) {
      if (e is! Directory) continue;
      final m = _slotDir.firstMatch(
        e.uri.pathSegments.lastWhere((s) => s != ''),
      );
      if (m == null) continue;
      final slot = int.parse(m.group(1)!);
      if (await _metaFile(slot).exists()) slots.add(slot);
    }
    slots.sort();
    return [
      for (final slot in slots)
        SlotInfo.fromJson(
          jsonDecode(await _metaFile(slot).readAsString())
              as Map<String, dynamic>,
        ),
    ];
  });

  @override
  Future<void> write(int slot, Uint8List bytes, SlotInfo meta) {
    _checkWrite(slot, meta);
    return _io(() async {
      await _dir(slot).create(recursive: true);
      final tmp = File('${_world(slot).path}.tmp');
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(_world(slot).path);
      await _metaFile(
        slot,
      ).writeAsString(jsonEncode(meta.toJson()), flush: true);
    });
  }

  @override
  Future<Uint8List> read(int slot) => _io(() async {
    final f = _world(slot);
    if (!await f.exists()) throw _missing(slot);
    return f.readAsBytes();
  });

  @override
  Future<void> delete(int slot) => _io(() async {
    final dir = _dir(slot);
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  static Future<T> _io<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on FileSystemException catch (e) {
      throw SaveError(SaveErrorKind.io, e.toString());
    }
  }
}
