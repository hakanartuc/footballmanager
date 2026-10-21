import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../engine/snapshots.dart';
import '../../l10n/formatters.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../state/game_controller.dart';
import '../widgets/club_chip.dart';
import '../widgets/loaded.dart';

/// The league tab: a country and league picker over a table tab and a
/// fixtures tab (the user's club, or a picked club while unemployed).
class LeagueScreen extends StatefulWidget {
  const LeagueScreen({super.key});

  @override
  State<LeagueScreen> createState() => _LeagueScreenState();
}

class _LeagueScreenState extends State<LeagueScreen> {
  /// The latest [Ready], shown while the controller is [Busy] or [Failed].
  Ready? _ready;

  /// The picked league; the user's (or the first) until changed.
  LeagueId? _leagueId;

  /// The club whose fixtures are listed while unemployed.
  ClubId? _pickedClubId;

  /// Refetched when home, the league or the listed club changes.
  Future<List<TableRowView>>? _table;
  Future<List<FixtureRow>>? _fixtures;

  void _setLeague(LeagueId id) => setState(() {
    _leagueId = id;
    _pickedClubId = null;
    _table = null;
    if (_ready!.home.clubId == null) _fixtures = null;
  });

  void _setClub(ClubId id) => setState(() {
    _pickedClubId = id;
    _fixtures = null;
  });

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<GameController>();
    final ready = switch (controller.state) {
      final Ready r => r,
      Failed(previous: final Ready r) => r,
      _ => _ready!,
    };
    if (!identical(ready.home, _ready?.home)) {
      _table = null;
      _fixtures = null;
    }
    _ready = ready;
    final l = AppLocalizations.of(context)!;
    final refs = ready.refs;
    final home = ready.home;

    _leagueId ??= home.leagueId ?? refs.leagues.first.id;
    final league = refs.leagues.firstWhere((x) => x.id == _leagueId);
    final userClubId = home.clubId;
    final fixturesClubId =
        userClubId ?? (_pickedClubId ??= league.clubIds.first);
    _table ??= controller.table(league.id);
    _fixtures ??= controller.clubFixtures(fixturesClubId);
    final clubs = {for (final c in refs.clubs) c.id: c};

    final picker = Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: DropdownButton<String>(
              isExpanded: true,
              value: league.countryCode,
              items: [
                for (final c in refs.countries)
                  DropdownMenuItem(
                    value: c.code,
                    child: Text(
                      countryName(c.code, l),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (code) => _setLeague(
                refs.leagues.firstWhere((x) => x.countryCode == code).id,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButton<LeagueId>(
              isExpanded: true,
              value: league.id,
              items: [
                for (final x in refs.leagues)
                  if (x.countryCode == league.countryCode)
                    DropdownMenuItem(
                      value: x.id,
                      child: Text(
                        leagueDisplayName(x.countryCode, x.tier, l),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
              ],
              onChanged: (id) => _setLeague(id!),
            ),
          ),
        ],
      ),
    );

    final clubPicker = userClubId != null
        ? null
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: DropdownButton<ClubId>(
              isExpanded: true,
              value: fixturesClubId,
              items: [
                for (final id in league.clubIds)
                  DropdownMenuItem(
                    value: id,
                    child: Text(
                      clubs[id]!.name,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (id) => _setClub(id!),
            ),
          );

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          picker,
          TabBar(
            tabs: [
              Tab(text: l.table),
              Tab(text: l.fixtures),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                Loaded(
                  future: _table!,
                  onRetry: () => setState(() => _table = null),
                  builder: (rows) => [
                    const _TableHeader(),
                    for (final r in rows) _TableRow(r, clubs[r.clubId]!),
                  ],
                ),
                Loaded(
                  future: _fixtures!,
                  onRetry: () => setState(() => _fixtures = null),
                  header: clubPicker,
                  builder: (rows) => [
                    for (final f in rows) _FixtureTile(f, userClubId),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

const _cellWidth = 28.0;
const _rankWidth = 24.0;

class _Cells extends StatelessWidget {
  const _Cells({required this.rank, required this.club, required this.cells});

  final String rank;
  final Widget club;
  final List<String> cells;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Row(
      children: [
        SizedBox(width: _rankWidth, child: Text(rank)),
        Expanded(child: club),
        for (final c in cells)
          SizedBox(
            width: _cellWidth,
            child: Text(c, textAlign: TextAlign.end),
          ),
      ],
    ),
  );
}

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return DefaultTextStyle.merge(
      style: Theme.of(context).textTheme.labelMedium,
      child: _Cells(
        rank: '#',
        club: const SizedBox(),
        cells: [l.played, l.won, l.drawn, l.lost, l.goalDifference, l.points],
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow(this.row, this.club);

  final TableRowView row;
  final ClubRef club;

  @override
  Widget build(BuildContext context) {
    final r = row;
    final cells = _Cells(
      rank: '${r.rank}',
      club: Row(
        children: [
          ClubChip(club, compact: true),
          const SizedBox(width: 6),
          Expanded(child: Text(r.clubName, overflow: TextOverflow.ellipsis)),
        ],
      ),
      cells: [
        '${r.played}',
        '${r.won}',
        '${r.drawn}',
        '${r.lost}',
        '${r.gd}',
        '${r.points}',
      ],
    );
    if (!r.isUser) return cells;
    return ColoredBox(
      key: const Key('userRow'),
      color: Theme.of(context).colorScheme.primaryContainer,
      child: cells,
    );
  }
}

class _FixtureTile extends StatelessWidget {
  const _FixtureTile(this.fixture, this.userClubId);

  final FixtureRow fixture;
  final ClubId? userClubId;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final f = fixture;
    final hg = f.homeGoals;
    final ag = f.awayGoals;
    final played = hg != null && ag != null;
    Text name(String text, ClubId id, TextAlign align) => Text(
      text,
      textAlign: align,
      overflow: TextOverflow.ellipsis,
      style: id == userClubId
          ? const TextStyle(fontWeight: FontWeight.bold)
          : null,
    );
    final title = Row(
      children: [
        Expanded(child: name(f.homeName, f.homeId, TextAlign.end)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(played ? '$hg - $ag' : '–'),
        ),
        Expanded(child: name(f.awayName, f.awayId, TextAlign.start)),
      ],
    );
    final subtitle = Text(
      '${l.roundLabel(f.round)} · '
      '${formatDate(f.date, Localizations.localeOf(context))}',
    );
    if (!played) return ListTile(title: title, subtitle: subtitle);

    Widget scorers(ClubId clubId, CrossAxisAlignment align) => Column(
      crossAxisAlignment: align,
      children: [
        for (final g in f.goals)
          if (g.clubId == clubId) Text("${g.minute}' ${g.scorerName}"),
      ],
    );
    return ExpansionTile(
      title: title,
      subtitle: subtitle,
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: scorers(f.homeId, CrossAxisAlignment.start)),
            Expanded(child: scorers(f.awayId, CrossAxisAlignment.end)),
          ],
        ),
      ],
    );
  }
}
