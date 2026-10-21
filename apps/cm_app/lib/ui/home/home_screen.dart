import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../engine/snapshots.dart';
import '../../l10n/event_text.dart';
import '../../l10n/formatters.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../state/game_controller.dart';
import '../widgets/club_chip.dart';
import 'outcome_presenter.dart';

/// The home tab: date and club header, the advance / play button, the next
/// match, the latest news and a squad status row.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.onOpenInbox, this.onOpenLineup});

  /// Called when a news item is tapped.
  final VoidCallback? onOpenInbox;

  /// Called by the lineup button on match days.
  final VoidCallback? onOpenLineup;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// The latest [Ready], shown while the controller is [Busy] or [Failed].
  Ready? _ready;

  /// The inbox, refetched whenever home changes.
  Future<List<InboxItem>>? _news;

  /// Runs [action], then shows the user's match result and the season end.
  ///
  /// [positionBefore] is the league position before the action: the
  /// season-ending advance always starts after the last round (the
  /// calendar's season end is a week past it), so it is final, while the
  /// refreshed home already shows the next season's empty table.
  Future<void> _act(
    Future<AdvanceOutcome?> Function() action,
    int? positionBefore,
  ) async {
    final outcome = await action();
    if (!mounted || outcome == null) return;
    await presentOutcome(
      context,
      context.read<GameController>(),
      outcome,
      positionBefore: positionBefore,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<GameController>();
    final state = controller.state;
    final ready = switch (state) {
      final Ready r => r,
      Failed(previous: final Ready r) => r,
      _ => _ready!,
    };
    if (!identical(ready.home, _ready?.home)) _news = controller.inbox();
    _ready = ready;
    final busy = state is Busy;
    final home = ready.home;
    final l = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context);
    final text = Theme.of(context).textTheme;
    ClubRef club(ClubId id) => ready.refs.clubs.firstWhere((c) => c.id == id);

    final league = home.leagueId == null
        ? null
        : ready.refs.leagues.firstWhere((x) => x.id == home.leagueId);
    final header = Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(formatDate(home.date, locale), style: text.headlineSmall),
            Text('${l.season} ${seasonLabel(home.seasonYear)}'),
            const SizedBox(height: 8),
            if (home.clubId == null)
              Text(l.noClubUnemployed)
            else ...[
              Text(home.clubName!, style: text.titleMedium),
              Text(
                [
                  leagueDisplayName(league!.countryCode, league.tier, l),
                  if (home.leaguePosition != null)
                    l.leaguePositionLabel(home.leaguePosition!),
                ].join(' · '),
              ),
            ],
          ],
        ),
      ),
    );

    const bigButton = Size.fromHeight(56);
    final buttons = home.isMatchDay
        ? [
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: bigButton),
              onPressed: busy
                  ? null
                  : () => _act(
                      () => controller.playMatch(const []),
                      home.leaguePosition,
                    ),
              child: Text(l.playMatch),
            ),
            if (widget.onOpenLineup case final open?) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: busy ? null : open,
                child: Text(l.lineup),
              ),
            ],
          ]
        : [
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: bigButton),
              onPressed: busy
                  ? null
                  : () => _act(controller.advance, home.leaguePosition),
              child: Text(l.advance),
            ),
          ];

    final next = home.nextMatch;
    final nextCard = next == null
        ? null
        : Card(
            key: const Key('nextMatchCard'),
            child: ListTile(
              title: Text(l.nextMatch),
              subtitle: Text(
                '${formatDate(next.date, locale)} · '
                '${next.isHome ? l.homeLabel : l.awayLabel}',
              ),
              trailing: ClubChip(club(next.isHome ? next.awayId : next.homeId)),
            ),
          );

    final news = FutureBuilder(
      future: _news,
      builder: (context, snap) => Column(
        children: [
          for (final item in (snap.data ?? const <InboxItem>[]).take(3))
            ListTile(
              title: Text(
                EventText.describe(item, l).title,
                style: item.read
                    ? null
                    : const TextStyle(fontWeight: FontWeight.bold),
              ),
              onTap: widget.onOpenInbox,
            ),
        ],
      ),
    );

    final status = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        Chip(label: Text(l.playerCount(home.seniorCount))),
        Chip(
          label: Text(l.squadStatus(home.injuredCount, home.suspendedCount)),
        ),
      ],
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        header,
        const SizedBox(height: 16),
        ...buttons,
        if (nextCard != null) ...[const SizedBox(height: 16), nextCard],
        const SizedBox(height: 16),
        Text(l.latestNews, style: text.titleMedium),
        news,
        const SizedBox(height: 16),
        status,
      ],
    );
  }
}
