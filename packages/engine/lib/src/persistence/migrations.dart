import 'save_codec.dart';

/// Upgrades a save envelope from schema [from] to `from + 1`.
///
/// [apply] receives and returns the whole envelope map
/// (`{"schemaVersion": from, "world": {...}}`); [migrate] sets the new
/// `schemaVersion` afterwards.
class Migration {
  final int from;
  final Map<String, dynamic> Function(Map<String, dynamic>) apply;

  const Migration({required this.from, required this.apply});
}

/// The registered migrations, one per schema step. Empty at schema v1.
const List<Migration> migrations = [];

/// Applies the migrations of [registry] (default [migrations]) in order until
/// [envelope] is at [currentSchemaVersion].
///
/// Throws [SaveError] `newerSchema` when the envelope is newer than this
/// engine and `corrupt` when a step is missing.
Map<String, dynamic> migrate(
  Map<String, dynamic> envelope, {
  List<Migration>? registry,
}) {
  final steps = registry ?? migrations;
  var version = envelope['schemaVersion'] as int;
  if (version > currentSchemaVersion) {
    throw SaveError(
      SaveErrorKind.newerSchema,
      'save is schema v$version, engine supports v$currentSchemaVersion',
    );
  }
  while (version < currentSchemaVersion) {
    final from = version;
    final step = steps.where((m) => m.from == from).firstOrNull;
    if (step == null) {
      throw SaveError(SaveErrorKind.corrupt, 'no migration from v$version');
    }
    envelope = step.apply(envelope);
    version = from + 1;
    envelope['schemaVersion'] = version;
  }
  return envelope;
}
