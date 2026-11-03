import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../engine/engine_gateway.dart';
import '../../engine/snapshots.dart';
import '../../l10n/formatters.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../state/game_controller.dart';
import '../widgets/error_card.dart';
import '../widgets/position_chip.dart';

/// Picks the starting 11 for the next match. Saving stores the lineup as
/// [GameController.pendingLineup]; the engine validates it again when the
/// match is played. Opens on the pending lineup when there is one.
class LineupScreen extends StatefulWidget {
  const LineupScreen({super.key, required this.clubId});

  final ClubId clubId;

  @override
  State<LineupScreen> createState() => _LineupScreenState();
}

class _LineupScreenState extends State<LineupScreen> {
  /// Null until loaded.
  Formation? _formation;

  /// The positions of [_formation]; `_starters[i]` fills `_slots[i]`.
  List<Position> _slots = const [];
  GatewayError? _error;

  /// The club's seniors and youth, which may all be picked.
  List<SquadRow> _players = const [];
  Map<PlayerId, SquadRow> _byId = const {};

  /// One entry per slot; null while the slot is empty.
  List<PlayerId?> _starters = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Loads the pending lineup, else the gateway's current one; the auto
  /// lineup with [auto].
  Future<void> _load({bool auto = false}) async {
    final c = context.read<GameController>();
    if (_error != null) setState(() => _error = null);
    try {
      final pending = auto ? null : c.pendingLineup;
      final Formation formation;
      final List<PlayerId> starters;
      if (pending != null) {
        formation = pending.formation;
        starters = pending.starters;
      } else {
        final view = await c.lineup(widget.clubId, auto: auto);
        formation = view.formation;
        starters = view.starters;
      }
      final seniors = await c.squad(widget.clubId);
      final youth = await c.squad(widget.clubId, youth: true);
      if (!mounted) return;
      final slots = formationSlots(formation);
      setState(() {
        _formation = formation;
        _slots = slots;
        _players = [...seniors, ...youth];
        _byId = {for (final p in _players) p.id: p};
        _starters = [
          for (var i = 0; i < slots.length; i++)
            i < starters.length ? starters[i] : null,
        ];
      });
    } on GatewayError catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  static bool _eligible(SquadRow r) => !r.injured && r.suspension == 0;

  /// The first problem with [_starters], in [LineupError] order.
  LineupError? _firstError() {
    final ids = _starters.whereType<PlayerId>().toList();
    if (ids.length != 11) return LineupError.notEleven;
    if (ids.toSet().length != ids.length) return LineupError.duplicate;
    final rows = [for (final id in ids) _byId[id]];
    if (rows.contains(null)) return LineupError.notInClub;
    if (rows.first!.position != Position.gk) return LineupError.noGoalkeeper;
    if (!rows.every((r) => _eligible(r!))) return LineupError.ineligible;
    return null;
  }

  void _save() {
    final error = _firstError();
    if (error != null) {
      final l = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(lineupErrorText(error, l))));
      return;
    }
    final starters = _starters.whereType<PlayerId>().toList();
    final bench =
        _players
            .where(
              (r) => !r.isYouth && _eligible(r) && !starters.contains(r.id),
            )
            .toList()
          ..sort((a, b) => b.ca.compareTo(a.ca));
    context.read<GameController>().pendingLineup = Lineup(
      formation: _formation!,
      starters: starters,
      bench: [for (final r in bench.take(7)) r.id],
    );
    Navigator.of(context).pop();
  }

  /// Lets the user pick the player for slot [i]: eligible players not
  /// already starting, those whose position is the slot's first, then by
  /// CA.
  Future<void> _pick(int i) async {
    final slot = _slots[i];
    final candidates =
        _players
            .where((r) => _eligible(r) && !_starters.contains(r.id))
            .toList()
          ..sort((a, b) {
            final fit = (b.position == slot ? 1 : 0).compareTo(
              a.position == slot ? 1 : 0,
            );
            return fit != 0 ? fit : b.ca.compareTo(a.ca);
          });
    final picked = await showModalBottomSheet<PlayerId>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          children: [
            for (final r in candidates)
              ListTile(
                leading: PositionChip(r.position),
                title: Text(r.name, overflow: TextOverflow.ellipsis),
                trailing: Text('${r.ca}'),
                onTap: () => Navigator.of(context).pop(r.id),
              ),
          ],
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _starters[i] = picked);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final formation = _formation;
    final error = _error;
    return Scaffold(
      appBar: AppBar(title: Text(l.lineup)),
      body: error != null
          ? Center(
              child: ErrorCard(
                error: error,
                onRetry: _load,
                onDismiss: () => Navigator.of(context).pop(),
              ),
            )
          : formation == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    formationLabel(formation, l),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      for (var i = 0; i < _slots.length; i++)
                        _slotTile(i, _slots[i]),
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _load(auto: true),
                            child: Text(l.autoLineup),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: _save,
                            child: Text(l.saveLineup),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _slotTile(int i, Position slot) {
    final row = _byId[_starters[i]];
    return ListTile(
      dense: true,
      leading: PositionChip(slot),
      title: Text(
        row?.name ?? '—',
        overflow: TextOverflow.ellipsis,
        style: row != null && !_eligible(row)
            ? TextStyle(color: Theme.of(context).colorScheme.error)
            : null,
      ),
      trailing: row == null ? null : Text('${row.ca}'),
      onTap: () => _pick(i),
    );
  }
}
