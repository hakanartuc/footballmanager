import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/entitlements.dart';
import '../../engine/snapshots.dart';
import '../../l10n/formatters.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../state/game_controller.dart';
import '../widgets/club_chip.dart';

/// The 16 country codes in world-size order: a [WorldSize] holds the first
/// `countryCount` of them.
final List<String> _countryCodes = [
  for (final c in CountryData.load().countries) c.code,
];

/// The new game form: manager name and nationality, world size, seed and
/// the starting club (or none).
///
/// Clubs only exist once a world is generated, so choosing one runs a
/// preview: [GameController.newGame] with the same seed and size but no
/// club, then the pickers over its [WorldRefs]. Starting generates the
/// world again with the chosen club; generation is fast enough for the
/// double cost. The preview stays loaded until then.
class NewGameScreen extends StatefulWidget {
  const NewGameScreen({super.key});

  @override
  State<NewGameScreen> createState() => _NewGameScreenState();
}

class _NewGameScreenState extends State<NewGameScreen> {
  final _form = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();

  /// A UI-layer input, not game state, so the wall clock is allowed.
  late final _seed = TextEditingController(
    text: '${DateTime.now().millisecondsSinceEpoch & 0x7fffffff}',
  );

  /// The smallest allowed size, for the fastest generation.
  late WorldSize _size = WorldSize.values.firstWhere(
    context.read<Entitlements>().allows,
  );
  String _nationality = _countryCodes.first;
  bool _unemployed = false;
  ClubRef? _club;

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _seed.dispose();
    super.dispose();
  }

  /// The manager's nationality must be a country of the world.
  List<String> get _nationalities =>
      _countryCodes.take(_size.countryCount).toList();

  NewGameSpec _spec({ClubId? startClubId}) => NewGameSpec(
    seed: int.parse(_seed.text),
    size: _size,
    managerFirstName: _firstName.text.trim(),
    managerLastName: _lastName.text.trim(),
    managerCountryCode: _nationality,
    startClubId: startClubId,
  );

  /// A club belongs to the preview of one seed and size; changing either
  /// drops it (the next pick generates a new preview).
  void _worldChanged() => _club = null;

  void _setSize(WorldSize size) => setState(() {
    _size = size;
    if (!_nationalities.contains(_nationality)) {
      _nationality = _nationalities.first;
    }
    _worldChanged();
  });

  /// Ends on the root route when an action failed, where the root shows
  /// the error; returns whether [GameController.state] is [Ready].
  bool _ready(GameController controller) {
    if (controller.state is Ready) return true;
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    return false;
  }

  Future<void> _pickClub() async {
    if (!_form.currentState!.validate()) return;
    final controller = context.read<GameController>();
    await controller.newGame(_spec());
    if (!_ready(controller)) return;
    final refs = await controller.refs();
    if (!mounted) return;
    final l = AppLocalizations.of(context)!;

    final country = await _choose(
      l.pickCountry,
      refs.countries,
      (c) => Text(countryName(c.code, l)),
    );
    if (country == null) return;
    final leagues = [
      for (final id in country.leagueIds)
        refs.leagues.firstWhere((x) => x.id == id),
    ];
    final league = await _choose(
      l.pickLeague,
      leagues,
      (x) => Text(leagueDisplayName(x.countryCode, x.tier, l)),
    );
    if (league == null) return;
    final club = await _choose(
      l.pickClub,
      [
        for (final c in refs.clubs)
          if (c.leagueId == league.id) c,
      ],
      (c) => Row(
        children: [
          ClubChip(c, compact: true),
          const SizedBox(width: 12),
          Expanded(child: Text(c.name)),
        ],
      ),
    );
    if (club != null) setState(() => _club = club);
  }

  /// One step of the club picker: [options] in a bottom sheet.
  Future<T?> _choose<T extends Object>(
    String title,
    List<T> options,
    Widget Function(T) label,
  ) {
    if (!mounted) return Future.value();
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final o in options)
                      ListTile(
                        title: label(o),
                        onTap: () => Navigator.of(context).pop(o),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _start() async {
    if (!_form.currentState!.validate()) return;
    final controller = context.read<GameController>();
    await controller.newGame(
      _spec(startClubId: _unemployed ? null : _club!.id),
    );
    if (_ready(controller) && mounted) {
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final entitlements = context.read<Entitlements>();
    final busy = context.watch<GameController>().state is Busy;
    String? required(String? v) =>
        (v == null || v.trim().isEmpty) ? l.fieldRequired : null;
    final club = _club;

    return Scaffold(
      appBar: AppBar(title: Text(l.newGame)),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              key: const Key('firstName'),
              controller: _firstName,
              decoration: InputDecoration(labelText: l.managerFirstName),
              textCapitalization: TextCapitalization.words,
              validator: required,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('lastName'),
              controller: _lastName,
              decoration: InputDecoration(labelText: l.managerLastName),
              textCapitalization: TextCapitalization.words,
              validator: required,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              // The options change with the size; rebuild the field then.
              key: ValueKey(_size),
              initialValue: _nationality,
              decoration: InputDecoration(labelText: l.nationality),
              items: [
                for (final code in _nationalities)
                  DropdownMenuItem(
                    value: code,
                    child: Text(countryName(code, l)),
                  ),
              ],
              onChanged: (v) => setState(() => _nationality = v!),
            ),
            const SizedBox(height: 16),
            Text(l.worldSize, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            SegmentedButton<WorldSize>(
              segments: [
                for (final s in WorldSize.values)
                  if (entitlements.allows(s))
                    ButtonSegment(value: s, label: Text(worldSizeName(s, l))),
              ],
              selected: {_size},
              onSelectionChanged: busy ? null : (s) => _setSize(s.single),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l.startUnemployed),
              value: _unemployed,
              onChanged: busy ? null : (v) => setState(() => _unemployed = v),
            ),
            if (!_unemployed)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: club == null ? null : ClubChip(club, compact: true),
                title: Text(club?.name ?? l.startClub),
                trailing: OutlinedButton(
                  onPressed: busy ? null : _pickClub,
                  child: Text(l.pickClub),
                ),
              ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(l.advanced),
              children: [
                TextFormField(
                  key: const Key('seed'),
                  controller: _seed,
                  decoration: InputDecoration(labelText: l.seed),
                  keyboardType: TextInputType.number,
                  validator: (v) =>
                      int.tryParse(v ?? '') == null ? l.fieldRequired : null,
                  onChanged: (_) => setState(_worldChanged),
                ),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: busy || (!_unemployed && club == null) ? null : _start,
              child: busy
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l.startGame),
            ),
          ],
        ),
      ),
    );
  }
}
