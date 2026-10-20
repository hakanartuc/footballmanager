import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../model/json.dart';
import '../model/world.dart';
import 'migrations.dart';

/// Schema version written into every save envelope.
const int currentSchemaVersion = 1;

enum SaveErrorKind { corrupt, newerSchema, missingSlot, io }

/// The only exception the persistence layer throws for bad saves or IO.
class SaveError implements Exception {
  final SaveErrorKind kind;
  final String message;

  SaveError(this.kind, this.message);

  @override
  String toString() => 'SaveError(${kind.name}): $message';
}

/// Turns a [World] into save bytes and back. Faz 4 replaces the JSON codec
/// with a binary one behind this interface.
abstract interface class SaveCodec {
  Uint8List encode(World w);

  /// Throws [SaveError] for corrupt or newer-schema bytes.
  World decode(Uint8List bytes);
}

/// `gzip(utf8(jsonEncode({"schemaVersion": v, "world": worldToJson(w)})))`.
///
/// The JSON is byte-stable and gzip runs at a fixed level, so encoding the
/// same world twice gives the same bytes on one platform. The gzip bytes may
/// differ between platforms (native zlib vs. pure Dart); the JSON inside is
/// the determinism oracle.
class JsonGzipSaveCodec implements SaveCodec {
  /// Migration registry used by [decode]; null means the built-in one.
  final List<Migration>? migrations;

  const JsonGzipSaveCodec({this.migrations});

  static const _gzipLevel = 6;

  @override
  Uint8List encode(World w) {
    final envelope = {
      'schemaVersion': currentSchemaVersion,
      'world': worldToJson(w),
    };
    return GZipEncoder().encodeBytes(
      utf8.encode(jsonEncode(envelope)),
      level: _gzipLevel,
    );
  }

  @override
  World decode(Uint8List bytes) {
    final Object? decoded;
    try {
      final json = utf8.decode(GZipDecoder().decodeBytes(bytes, verify: true));
      decoded = jsonDecode(json);
    } catch (e) {
      throw SaveError(SaveErrorKind.corrupt, 'unreadable save: $e');
    }
    if (decoded is! Map<String, dynamic> ||
        decoded['schemaVersion'] is! int ||
        decoded['world'] is! Map<String, dynamic>) {
      throw SaveError(SaveErrorKind.corrupt, 'not a save envelope');
    }

    final envelope = migrate(decoded, registry: migrations);
    final World world;
    try {
      world = worldFromJson(envelope['world'] as Map<String, dynamic>);
    } on TypeError catch (e) {
      throw SaveError(SaveErrorKind.corrupt, e.toString());
    } on FormatException catch (e) {
      throw SaveError(SaveErrorKind.corrupt, e.message);
    } on ArgumentError catch (e) {
      throw SaveError(SaveErrorKind.corrupt, e.toString());
    }
    world.schemaVersion = currentSchemaVersion;
    return world;
  }
}
