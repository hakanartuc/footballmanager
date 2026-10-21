import 'package:engine/engine.dart';

import 'engine_gateway.dart';
import 'snapshots.dart';

/// Builds the snapshots of `snapshots.dart` from a live [EngineSession].
/// Synchronous; the gateways wrap it in futures.
class SnapshotBuilder {
  SnapshotBuilder(this.s);

  final EngineSession s;

  World get _w => s.world;

  WorldRefs refs() => WorldRefs(
    countries: [
      for (final c in _w.countries.values)
        CountryRef(
          id: c.id,
          code: c.code,
          name: c.name,
          leagueIds: List.of(c.tiers),
        ),
    ],
    leagues: [
      for (final l in _w.leagues.values)
        LeagueRef(
          id: l.id,
          name: l.name,
          countryCode: _w.countries[l.countryId]!.code,
          tier: l.tier,
          clubIds: List.of(l.clubIds),
        ),
    ],
    clubs: [
      for (final c in _w.clubs.values)
        ClubRef(
          id: c.id,
          name: c.name,
          shortName: c.shortName,
          kitPrimary: c.home.primary,
          kitSecondary: c.home.secondary,
          leagueId: c.leagueId,
          countryId: c.countryId,
        ),
    ],
  );

  HomeSnapshot home() {
    final club = _w.userClub;
    final manager = _w.managers[_w.userManagerId]!;
    final seniors = club == null
        ? const <Player>[]
        : [for (final id in _w.squadOf(club.id)) _w.players[id]!];
    return HomeSnapshot(
      date: _w.date,
      seasonYear: _w.seasonYear,
      clubId: club?.id,
      clubName: club?.name,
      leagueId: club?.leagueId,
      leaguePosition: club == null ? null : _rankOf(club),
      nextMatch: club == null ? null : _nextMatch(club),
      isMatchDay: s.nextUserMatchDate() == _w.date,
      unreadCount: _w.inbox.where((m) => !m.read).length,
      seniorCount: seniors.length,
      injuredCount: seniors.where((p) => p.state.injury != null).length,
      suspendedCount: seniors
          .where((p) => p.state.suspensionMatches > 0)
          .length,
      managerName: '${manager.firstName} ${manager.lastName}',
    );
  }

  int _rankOf(Club club) =>
      s.table(club.leagueId).indexWhere((r) => r.clubId == club.id) + 1;

  NextMatch? _nextMatch(Club club) {
    for (final id in _w.fixturesOfClub(club.id, _w.seasonYear)) {
      final f = _w.fixtures[id]!;
      if (f.result != null || f.date.isBefore(_w.date)) continue;
      return NextMatch(
        fixtureId: f.id,
        date: f.date,
        homeId: f.homeId,
        awayId: f.awayId,
        homeName: _w.clubs[f.homeId]!.name,
        awayName: _w.clubs[f.awayId]!.name,
        isHome: f.homeId == club.id,
      );
    }
    return null;
  }

  /// Sorted by position group, then CA descending, then id.
  List<SquadRow> squad(ClubId clubId, {bool youth = false}) {
    final players = youth ? s.youth(clubId) : s.squad(clubId);
    players.sort((a, b) {
      var c = a.mainPosition.group.index.compareTo(b.mainPosition.group.index);
      if (c != 0) return c;
      c = b.ca.compareTo(a.ca);
      return c != 0 ? c : a.id.compareTo(b.id);
    });
    return [
      for (final p in players)
        SquadRow(
          id: p.id,
          name: _name(p),
          position: p.mainPosition,
          age: p.ageAt(_w.date),
          ca: p.ca,
          condition: p.state.condition,
          injured: p.state.injury != null,
          suspension: p.state.suspensionMatches,
          status: p.contract!.status,
          isYouth: p.isYouth,
        ),
    ];
  }

  PlayerDetail player(PlayerId id) {
    final p = _w.players[id];
    if (p == null) {
      throw const GatewayError(GatewayErrorKind.engine, 'no such player');
    }
    return PlayerDetail(
      id: p.id,
      name: _name(p),
      countryCode: _w.countries[p.nationality]!.code,
      position: p.mainPosition,
      familiarity: Map.of(p.familiarity),
      age: p.ageAt(_w.date),
      heightCm: p.heightCm,
      attrs: p.attrs.toList(),
      ca: p.ca,
      pa: p.pa,
      condition: p.state.condition,
      morale: p.state.morale,
      sharpness: p.state.sharpness,
      form: p.state.form,
      wageWeekly: p.contract?.wageWeekly,
      contractEnd: p.contract?.end,
      status: p.contract?.status,
      apps: p.season.apps,
      goals: p.season.goals,
      assists: p.season.assists,
    );
  }

  /// The stored lineup with its errors, or the auto lineup when none is
  /// stored or [auto] is true.
  LineupView lineup(ClubId clubId, {bool auto = false}) {
    final club = _w.clubs[clubId];
    if (club == null) {
      throw const GatewayError(GatewayErrorKind.engine, 'no such club');
    }
    final stored = auto ? null : club.lineup;
    final l = stored ?? autoLineup(_w, clubId);
    return LineupView(
      formation: l.formation,
      slots: formationSlots(l.formation),
      starters: List.of(l.starters),
      bench: List.of(l.bench),
      errors: stored == null ? const [] : validateLineup(_w, clubId, stored),
    );
  }

  List<TableRowView> table(LeagueId leagueId) {
    if (!_w.leagues.containsKey(leagueId)) {
      throw const GatewayError(GatewayErrorKind.engine, 'no such league');
    }
    final userClubId = _w.userClub?.id;
    final rows = s.table(leagueId);
    return [
      for (final (i, r) in rows.indexed)
        TableRowView(
          rank: i + 1,
          clubId: r.clubId,
          clubName: _w.clubs[r.clubId]!.name,
          played: r.played,
          won: r.won,
          drawn: r.drawn,
          lost: r.lost,
          gf: r.gf,
          ga: r.ga,
          gd: r.gd,
          points: r.points,
          isUser: r.clubId == userClubId,
        ),
    ];
  }

  List<FixtureRow> clubFixtures(ClubId clubId) => [
    for (final f in s.clubFixtures(clubId)) _fixtureRow(f),
  ];

  /// The row of fixture [id].
  FixtureRow fixture(FixtureId id) => _fixtureRow(_w.fixtures[id]!);

  FixtureRow _fixtureRow(Fixture f) {
    final r = f.result;
    return FixtureRow(
      id: f.id,
      round: f.round,
      date: f.date,
      homeId: f.homeId,
      awayId: f.awayId,
      homeName: _w.clubs[f.homeId]!.name,
      awayName: _w.clubs[f.awayId]!.name,
      homeGoals: r?.homeGoals,
      awayGoals: r?.awayGoals,
      goals: [
        if (r != null)
          for (final g in r.goals)
            GoalRow(
              minute: g.minute,
              scorerId: g.scorerId,
              scorerName: _name(_w.players[g.scorerId]!),
              clubId: g.clubId,
            ),
      ],
    );
  }

  /// Newest first.
  List<InboxItem> inbox() => [
    for (final m in s.inbox())
      InboxItem(
        id: m.id,
        date: m.date,
        read: m.read,
        event: m.event,
        labels: _labels(m.event),
      ),
  ];

  InboxLabels _labels(GameEvent e) {
    String clubName(ClubId id) => _w.clubs[id]!.name;
    String leagueName(LeagueId id) => _w.leagues[id]!.name;
    String leagueCountry(LeagueId id) =>
        _w.countries[_w.leagues[id]!.countryId]!.code;
    int leagueTier(LeagueId id) => _w.leagues[id]!.tier;
    return switch (e) {
      MatchPlayed(:final fixtureId) => () {
        final f = _w.fixtures[fixtureId]!;
        return InboxLabels(
          homeName: clubName(f.homeId),
          awayName: clubName(f.awayId),
          homeGoals: f.result!.homeGoals,
          awayGoals: f.result!.awayGoals,
        );
      }(),
      LeagueChampion(:final clubId, :final leagueId) => InboxLabels(
        clubName: clubName(clubId),
        leagueName: leagueName(leagueId),
        leagueCountryCode: leagueCountry(leagueId),
        leagueTier: leagueTier(leagueId),
      ),
      Promoted(:final clubId, :final fromLeagueId, :final toLeagueId) ||
      Relegated(
        :final clubId,
        :final fromLeagueId,
        :final toLeagueId,
      ) => InboxLabels(
        clubName: clubName(clubId),
        leagueName: leagueName(fromLeagueId),
        leagueCountryCode: leagueCountry(fromLeagueId),
        leagueTier: leagueTier(fromLeagueId),
        toLeagueName: leagueName(toLeagueId),
        toLeagueCountryCode: leagueCountry(toLeagueId),
        toLeagueTier: leagueTier(toLeagueId),
      ),
      PlayerRetired(:final clubId) => InboxLabels(
        clubName: clubId == null ? null : clubName(clubId),
      ),
      YouthIntake(:final clubId, :final playerIds) => InboxLabels(
        clubName: clubName(clubId),
        playerNames: [
          for (final id in playerIds)
            if (_w.players[id] case final p?) _name(p),
        ],
      ),
      YouthReleased(:final clubId) => InboxLabels(clubName: clubName(clubId)),
      SeasonEnded() || NewSeasonStarted() => const InboxLabels(),
    };
  }

  static String _name(Player p) => '${p.firstName} ${p.lastName}';
}
