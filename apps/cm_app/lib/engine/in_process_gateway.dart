import 'dart:typed_data';

import 'package:engine/engine.dart';

import 'engine_gateway.dart';
import 'snapshot_builder.dart';
import 'snapshots.dart';

/// An [EngineGateway] that runs the engine on the calling isolate. Used by
/// tests and as the body of the isolate gateway.
class InProcessGateway implements EngineGateway {
  InProcessGateway({this.sim});

  final MatchSimulator? sim;
  EngineSession? _session;

  EngineSession get _s => _session ?? (throw StateError('no game'));

  /// Runs [body], turning anything it throws into a failed future with a
  /// [GatewayError].
  Future<T> _run<T>(T Function() body) => Future.sync(() {
    try {
      return body();
    } on GatewayError {
      rethrow;
    } on SaveError catch (e) {
      throw GatewayError(GatewayErrorKind.save, e.message);
    } on StateError catch (e) {
      if (e.message == 'no game') {
        throw GatewayError(GatewayErrorKind.noGame, e.message);
      }
      throw GatewayError(GatewayErrorKind.engine, e.toString());
    } catch (e) {
      throw GatewayError(GatewayErrorKind.engine, e.toString());
    }
  });

  Future<T> _build<T>(T Function(SnapshotBuilder b) body) =>
      _run(() => body(SnapshotBuilder(_s)));

  @override
  Future<void> newGame(NewGameSpec spec) =>
      _run(() => _session = EngineSession.newGame(spec, sim: sim));

  @override
  Future<void> load(Uint8List bytes) =>
      _run(() => _session = EngineSession.fromBytes(bytes, sim: sim));

  @override
  Future<Uint8List> save() => _run(() => _s.save());

  @override
  Future<AdvanceOutcome> advanceToNext({int maxDays = 90}) => _run(() {
    final s = _s;
    final w = s.world;
    final start = w.date;
    final inboxBefore = _lastInboxId(w);
    final summaries = s.advanceUntil(start.addDays(maxDays));
    final seasonEnded =
        summaries.isNotEmpty &&
        summaries.last.events.any((e) => e is SeasonEnded);
    return AdvanceOutcome(
      daysAdvanced: start.daysUntil(w.date),
      reason: s.nextUserMatchDate() == w.date
          ? StopReason.matchDay
          : seasonEnded
          ? StopReason.seasonEnded
          : StopReason.reachedLimit,
      date: w.date,
      userMatch: null,
      seasonEnded: seasonEnded,
      newInboxCount: _lastInboxId(w) - inboxBefore,
    );
  });

  @override
  Future<AdvanceOutcome> playToday(List<Command> commands) => _run(() {
    final s = _s;
    final w = s.world;
    final clubId = w.userClub?.id;
    final inboxBefore = _lastInboxId(w);
    final summary = s.advanceDay(commands);
    final userFixtureId = summary.playedFixtures.where((id) {
      final f = w.fixtures[id]!;
      return f.homeId == clubId || f.awayId == clubId;
    }).firstOrNull;
    return AdvanceOutcome(
      daysAdvanced: 1,
      reason: StopReason.played,
      date: w.date,
      userMatch: userFixtureId == null
          ? null
          : SnapshotBuilder(s).fixture(userFixtureId),
      seasonEnded: summary.events.any((e) => e is SeasonEnded),
      newInboxCount: _lastInboxId(w) - inboxBefore,
    );
  });

  /// Inbox ids are issued in increasing order, so the last message holds
  /// the highest id and the difference between two readings counts the
  /// messages added in between, whatever was trimmed from the front.
  static int _lastInboxId(World w) => w.inbox.lastOrNull?.id ?? 0;

  @override
  Future<WorldRefs> refs() => _build((b) => b.refs());

  @override
  Future<HomeSnapshot> home() => _build((b) => b.home());

  @override
  Future<List<SquadRow>> squad(ClubId clubId, {bool youth = false}) =>
      _build((b) => b.squad(clubId, youth: youth));

  @override
  Future<PlayerDetail> player(PlayerId id) => _build((b) => b.player(id));

  @override
  Future<LineupView> lineup(ClubId clubId, {bool auto = false}) =>
      _build((b) => b.lineup(clubId, auto: auto));

  @override
  Future<List<TableRowView>> table(LeagueId leagueId) =>
      _build((b) => b.table(leagueId));

  @override
  Future<List<FixtureRow>> clubFixtures(ClubId clubId) =>
      _build((b) => b.clubFixtures(clubId));

  @override
  Future<List<InboxItem>> inbox() => _build((b) => b.inbox());

  @override
  Future<void> markRead(int inboxId) => _run(() => _s.markReadById(inboxId));

  @override
  Future<void> dispose() async {
    _session = null;
  }
}
