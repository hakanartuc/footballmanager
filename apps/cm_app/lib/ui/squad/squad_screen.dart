import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../engine/engine_gateway.dart';
import '../../engine/snapshots.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../state/game_controller.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_card.dart';
import '../widgets/position_chip.dart';
import 'player_screen.dart';

/// The squad tab: the user's seniors or youth, grouped by position group.
class SquadScreen extends StatefulWidget {
  const SquadScreen({super.key});

  @override
  State<SquadScreen> createState() => _SquadScreenState();
}

class _SquadScreenState extends State<SquadScreen> {
  /// The latest [Ready], shown while the controller is [Busy] or [Failed].
  Ready? _ready;
  bool _youth = false;

  /// The listed squad, refetched when home or [_youth] changes.
  Future<List<SquadRow>>? _rows;

  void _setYouth(bool youth) => setState(() {
    _youth = youth;
    _rows = null;
  });

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<GameController>();
    final ready = switch (controller.state) {
      final Ready r => r,
      Failed(previous: final Ready r) => r,
      _ => _ready!,
    };
    if (!identical(ready.home, _ready?.home)) _rows = null;
    _ready = ready;
    final l = AppLocalizations.of(context)!;
    final clubId = ready.home.clubId;
    if (clubId == null) return EmptyState(text: l.noClubUnemployed);
    _rows ??= controller.squad(clubId, youth: _youth);

    final toggle = Padding(
      padding: const EdgeInsets.all(16),
      child: SegmentedButton<bool>(
        segments: [
          ButtonSegment(value: false, label: Text(l.seniorSquad)),
          ButtonSegment(value: true, label: Text(l.youthSquad)),
        ],
        selected: {_youth},
        onSelectionChanged: (s) => _setYouth(s.single),
      ),
    );

    return FutureBuilder(
      future: _rows,
      builder: (context, snap) {
        final rows = snap.data ?? const <SquadRow>[];
        return ListView(
          children: [
            toggle,
            if (snap.error case final GatewayError e)
              ErrorCard(error: e, onRetry: () => setState(() => _rows = null))
            else if (snap.connectionState != ConnectionState.done)
              const Center(child: CircularProgressIndicator()),
            for (final group in PositionGroup.values)
              if (rows.any((r) => r.position.group == group)) ...[
                _GroupHeader(_groupName(group, l)),
                for (final r in rows)
                  if (r.position.group == group) _SquadTile(r),
              ],
          ],
        );
      },
    );
  }
}

String _groupName(PositionGroup g, AppLocalizations l) => switch (g) {
  PositionGroup.gk => l.groupGoalkeepers,
  PositionGroup.def => l.groupDefenders,
  PositionGroup.mid => l.groupMidfielders,
  PositionGroup.att => l.groupForwards,
};

class _GroupHeader extends StatelessWidget {
  const _GroupHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}

class _SquadTile extends StatelessWidget {
  const _SquadTile(this.row);

  final SquadRow row;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final r = row;
    return ListTile(
      leading: PositionChip(r.position),
      title: Text(
        r.name,
        style: const TextStyle(fontWeight: FontWeight.bold),
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Row(
        children: [
          Flexible(
            child: Text(
              '${l.age} ${r.age} · ${l.ca} ${r.ca}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 64,
            child: Tooltip(
              message: l.condition,
              child: LinearProgressIndicator(value: r.condition / 100),
            ),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (r.injured) const Icon(Icons.healing, color: Colors.red),
          if (r.suspension > 0) const Icon(Icons.block),
        ],
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => PlayerScreen(playerId: r.id)),
      ),
    );
  }
}
