import 'package:engine/engine.dart';
import 'package:flutter/foundation.dart';

import '../data/game_repository.dart';
import '../engine/engine_gateway.dart';
import '../engine/snapshots.dart';

sealed class GameState {
  const GameState();
}

final class NoGame extends GameState {
  const NoGame();
}

final class Busy extends GameState {
  const Busy(this.what);

  /// The running action, e.g. `'advance'`.
  final String what;
}

final class Ready extends GameState {
  const Ready(this.home, this.refs);

  final HomeSnapshot home;
  final WorldRefs refs;
}

final class Failed extends GameState {
  const Failed(this.error, this.previous);

  final GatewayError error;

  /// The settled state ([NoGame] or [Ready]) before the failed action.
  final GameState previous;
}

/// The app's game state machine over a [GameRepository].
///
/// Actions throw [StateError] while [state] is [Busy]. A failing action
/// leaves [state] [Failed]; [retry] re-runs it.
class GameController extends ChangeNotifier {
  GameController(this._repo, this._gateway);

  final GameRepository _repo;
  final EngineGateway _gateway;

  GameState _state = const NoGame();
  GameState get state => _state;

  int lastAdvanceMs = 0;
  int lastSaveMs = 0;

  /// Sent as a [SetLineup] by the next successful [playMatch].
  Lineup? pendingLineup;

  Future<void> Function()? _lastAction;

  Future<void> newGame(NewGameSpec spec) => _run('newGame', (_) async {
    await _repo.newGame(spec);
    await _refresh(null);
  });

  /// Loads the newest autosave; stays [NoGame] when there is none.
  Future<void> continueLast() => _run('continueLast', (previous) async {
    if (await _repo.continueLast()) {
      await _refresh(null);
    } else {
      _set(previous);
    }
  });

  Future<void> loadSlot(int slot) => _run('loadSlot', (_) async {
    await _repo.loadSlot(slot);
    await _refresh(null);
  });

  Future<void> saveToSlot(int slot) => _run('saveToSlot', (previous) async {
    final sw = Stopwatch()..start();
    await _repo.saveToSlot(slot);
    lastSaveMs = sw.elapsedMilliseconds;
    _set(previous);
  });

  /// Advances to the next stop, autosaves and refreshes home.
  Future<AdvanceOutcome?> advance() => _run('advance', (previous) async {
    final sw = Stopwatch()..start();
    final outcome = await _gateway.advanceToNext();
    await _repo.autosave();
    await _refresh(previous);
    lastAdvanceMs = sw.elapsedMilliseconds;
    return outcome;
  });

  /// Plays today with [pendingLineup] (if any) and [extra], autosaves and
  /// refreshes home.
  Future<AdvanceOutcome?> playMatch(List<Command> extra) =>
      _run('playMatch', (previous) async {
        final home = (previous as Ready).home;
        final lineup = pendingLineup;
        final outcome = await _gateway.playToday([
          if (lineup != null) SetLineup(clubId: home.clubId!, lineup: lineup),
          ...extra,
        ]);
        await _repo.autosave();
        await _refresh(previous);
        pendingLineup = null;
        return outcome;
      });

  Future<void> refreshHome() => _run('refreshHome', _refresh, busy: false);

  /// Marks an inbox item read and refreshes home for the unread badge.
  Future<void> markRead(int id) => _run('markRead', (previous) async {
    await _gateway.markRead(id);
    await _refresh(previous);
  }, busy: false);

  /// Re-runs the last action.
  Future<void> retry() async => _lastAction?.call();

  Future<List<SquadRow>> squad(ClubId clubId, {bool youth = false}) =>
      _gateway.squad(clubId, youth: youth);
  Future<PlayerDetail> player(PlayerId id) => _gateway.player(id);
  Future<LineupView> lineup(ClubId clubId) => _gateway.lineup(clubId);
  Future<List<TableRowView>> table(LeagueId leagueId) =>
      _gateway.table(leagueId);
  Future<List<FixtureRow>> clubFixtures(ClubId clubId) =>
      _gateway.clubFixtures(clubId);
  Future<List<InboxItem>> inbox() => _gateway.inbox();
  Future<WorldRefs> refs() => _gateway.refs();

  /// [state] without a [Failed] wrapper.
  GameState get _settled => switch (_state) {
    Failed(:final previous) => previous,
    final s => s,
  };

  void _set(GameState s) {
    _state = s;
    notifyListeners();
  }

  /// Fetches home and sets [Ready], reusing [previous]'s refs when it is
  /// [Ready] (refs are fixed per game) and fetching them otherwise.
  Future<void> _refresh(GameState? previous) async {
    final home = await _gateway.home();
    final refs = previous is Ready ? previous.refs : await _gateway.refs();
    _set(Ready(home, refs));
  }

  /// Runs [body] with the settled state before it; [body] sets the final
  /// state. Errors set [Failed].
  Future<T?> _run<T>(
    String what,
    Future<T> Function(GameState previous) body, {
    bool busy = true,
  }) async {
    if (_state is Busy) throw StateError('busy');
    final previous = _settled;
    _lastAction = () => _run(what, body, busy: busy);
    if (busy) _set(Busy(what));
    try {
      return await body(previous);
    } on GatewayError catch (e) {
      _set(Failed(e, previous));
    } on SaveError catch (e) {
      _set(Failed(GatewayError(GatewayErrorKind.save, e.message), previous));
    } catch (e) {
      _set(Failed(GatewayError(GatewayErrorKind.engine, '$e'), previous));
      rethrow;
    }
    return null;
  }
}
