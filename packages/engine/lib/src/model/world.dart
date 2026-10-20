import '../core/game_date.dart';
import '../core/ids.dart';
import 'calendar.dart';
import 'club.dart';
import 'country.dart';
import 'events.dart';
import 'fixture.dart';
import 'manager.dart';
import 'player.dart';

class SeasonArchive {
  int seasonYear;
  Map<LeagueId, ClubId> champions;

  /// Final table order per league, champion first.
  Map<LeagueId, List<ClubId>> finalOrder;

  SeasonArchive({
    required this.seasonYear,
    required this.champions,
    required this.finalOrder,
  });
}

/// The whole game state.
///
/// The squad and fixture queries read derived indexes that are not
/// serialized. They are built by the constructor; callers must call
/// [rebuildIndexes] after any structural change (player moves, youth
/// promotion, fixture creation).
class World {
  int schemaVersion;
  int seed;
  GameDate date;
  int seasonYear;
  Map<CountryId, Country> countries;
  Map<LeagueId, League> leagues;
  Map<ClubId, Club> clubs;
  Map<PlayerId, Player> players;
  Map<ManagerId, Manager> managers;
  Map<FixtureId, Fixture> fixtures;
  SeasonCalendar calendar;
  ManagerId userManagerId;
  List<InboxMessage> inbox;
  List<SeasonArchive> history;
  IdAllocator ids;

  Map<ClubId, List<PlayerId>> _squadByClub = {};
  Map<ClubId, List<PlayerId>> _youthByClub = {};
  Map<int, List<FixtureId>> _fixturesByDate = {};
  Map<(ClubId, int), List<FixtureId>> _fixturesByClubSeason = {};
  Map<(LeagueId, int), List<FixtureId>> _fixturesByLeagueSeason = {};

  World({
    required this.schemaVersion,
    required this.seed,
    required this.date,
    required this.seasonYear,
    required this.countries,
    required this.leagues,
    required this.clubs,
    required this.players,
    required this.managers,
    required this.fixtures,
    required this.calendar,
    required this.userManagerId,
    required this.ids,
    List<InboxMessage>? inbox,
    List<SeasonArchive>? history,
  }) : inbox = inbox ?? [],
       history = history ?? [] {
    rebuildIndexes();
  }

  /// Recomputes the squad and fixture indexes from [players] and [fixtures].
  void rebuildIndexes() {
    final squad = <ClubId, List<PlayerId>>{};
    final youth = <ClubId, List<PlayerId>>{};
    for (final p in players.values) {
      final clubId = p.contract?.clubId;
      if (clubId == null) continue;
      (p.isYouth ? youth : squad).putIfAbsent(clubId, () => []).add(p.id);
    }
    for (final list in [...squad.values, ...youth.values]) {
      list.sort();
    }

    final byDate = <int, List<FixtureId>>{};
    final byClubSeason = <(ClubId, int), List<FixtureId>>{};
    final sorted = fixtures.values.toList()
      ..sort((a, b) {
        final c = a.date.dayIndex.compareTo(b.date.dayIndex);
        return c != 0 ? c : a.id.compareTo(b.id);
      });
    for (final f in sorted) {
      byDate.putIfAbsent(f.date.dayIndex, () => []).add(f.id);
      for (final c in [f.homeId, f.awayId]) {
        byClubSeason.putIfAbsent((c, f.seasonYear), () => []).add(f.id);
      }
    }
    final byLeagueSeason = <(LeagueId, int), List<FixtureId>>{};
    for (final f in fixtures.values) {
      byLeagueSeason
          .putIfAbsent((f.leagueId, f.seasonYear), () => [])
          .add(f.id);
    }
    for (final list in byLeagueSeason.values) {
      list.sort();
    }

    _squadByClub = squad;
    _youthByClub = youth;
    _fixturesByDate = byDate;
    _fixturesByClubSeason = byClubSeason;
    _fixturesByLeagueSeason = byLeagueSeason;
  }

  /// Senior players contracted to [c], sorted by id.
  List<PlayerId> squadOf(ClubId c) => _view(_squadByClub[c]);

  /// Youth players contracted to [c], sorted by id.
  List<PlayerId> youthOf(ClubId c) => _view(_youthByClub[c]);

  /// Fixtures on [d], sorted by id.
  List<FixtureId> fixturesOn(GameDate d) => _view(_fixturesByDate[d.dayIndex]);

  /// [c]'s fixtures in [seasonYear], sorted by date then id.
  List<FixtureId> fixturesOfClub(ClubId c, int seasonYear) =>
      _view(_fixturesByClubSeason[(c, seasonYear)]);

  /// League [l]'s fixtures in [seasonYear], sorted by id.
  List<FixtureId> fixturesOfLeagueSeason(LeagueId l, int seasonYear) =>
      _view(_fixturesByLeagueSeason[(l, seasonYear)]);

  /// The user's club; null when the user manager is unemployed.
  Club? get userClub {
    final clubId = managers[userManagerId]?.clubId;
    return clubId == null ? null : clubs[clubId];
  }

  static List<int> _view(List<int>? ids) =>
      ids == null ? const [] : List.unmodifiable(ids);
}
