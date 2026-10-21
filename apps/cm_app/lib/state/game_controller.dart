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
  const Ready(this.home, this.refs, this.gameId);

  final HomeSnapshot home;
  final WorldRefs refs;

  /// Changes whenever a game is started or loaded, so per-game UI state
  /// keyed on it is dropped.
  final int gameId;
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
/// leaves [state] [Failed]; [retry] re-runs it, [dismissError] drops it.
class GameController extends ChangeNotifier {
  GameController(this._repo, this._gateway);

  final GameRepository _repo;
  final EngineGateway _gateway;

  GameState _state = const NoGame();
  GameState get state => _state;

  /// See [Ready.gameId].
  int _gameId = 0;

  int lastAdvanceMs = 0;
  int lastSaveMs = 0;

  /// Sent as a [SetLineup] by the next successful [playMatch]; dropped when
  /// another game is started, loaded or previewed.
  Lineup? pendingLineup;

  Future<Object?> Function()? _lastAction;

  Future<void> newGame(NewGameSpec spec) => _run('newGame', (_) async {
    await _repo.newGame(spec);
    await _enterGame();
  });

  /// Generates [spec]'s world without a club and returns its refs, for the
  /// new-game club picker; null when it failed. Only from [NoGame], which
  /// [state] stays in: nothing is autosaved and the preview is replaced by
  /// the next [newGame]. [retry] after a failed preview does nothing.
  Future<WorldRefs?> previewWorld(NewGameSpec spec) async {
    if (_state is Busy) throw StateError('busy');
    if (_settled is! NoGame) throw StateError('previewWorld needs NoGame');
    pendingLineup = null;
    final refs = await _run('preview', (previous) async {
      await _gateway.newGame(
        NewGameSpec(
          seed: spec.seed,
          size: spec.size,
          managerFirstName: spec.managerFirstName,
          managerLastName: spec.managerLastName,
          managerCountryCode: spec.managerCountryCode,
          startClubId: null,
        ),
      );
      final refs = await _gateway.refs();
      _set(previous);
      return refs;
    });
    _lastAction = () async => null;
    return refs;
  }

  /// Loads the newest autosave; stays [NoGame] when there is none.
  Future<void> continueLast() => _run('continueLast', (previous) async {
    if (await _repo.continueLast()) {
      await _enterGame();
    } else {
      _set(previous);
    }
  });

  Future<void> loadSlot(int slot) => _run('loadSlot', (_) async {
    await _repo.loadSlot(slot);
    await _enterGame();
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
    await _autosaveAfterMutation(previous, outcome);
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
        pendingLineup = null;
        await _autosaveAfterMutation(previous, outcome);
        return outcome;
      });

  Future<void> refreshHome() =>
      _run('refreshHome', (p) => _refresh(p, unlessBusy: true), busy: false);

  /// Marks an inbox item read and refreshes home for the unread badge.
  Future<void> markRead(int id) => _run('markRead', (previous) async {
    await _gateway.markRead(id);
    await _refresh(previous, unlessBusy: true);
  }, busy: false);

  /// Re-runs the last action; returns its outcome when it was [advance] or
  /// [playMatch] (or the autosave after one, whose outcome is kept), else
  /// null.
  Future<AdvanceOutcome?> retry() async {
    final result = await _lastAction?.call();
    return result is AdvanceOutcome ? result : null;
  }

  /// Leaves [Failed] for its previous state without retrying.
  void dismissError() {
    if (_state case Failed(:final previous)) _set(previous);
  }

  Future<List<SquadRow>> squad(ClubId clubId, {bool youth = false}) =>
      _gateway.squad(clubId, youth: youth);
  Future<PlayerDetail> player(PlayerId id) => _gateway.player(id);
  Future<LineupView> lineup(ClubId clubId, {bool auto = false}) =>
      _gateway.lineup(clubId, auto: auto);
  Future<List<TableRowView>> table(LeagueId leagueId) =>
      _gateway.table(leagueId);
  Future<List<FixtureRow>> clubFixtures(ClubId clubId) =>
      _gateway.clubFixtures(clubId);
  Future<List<InboxItem>> inbox() => _gateway.inbox();
  Future<WorldRefs> refs() => _gateway.refs();
  Future<SlotInfo?> newestAutosave() => _repo.newestAutosave();
  Future<List<SlotInfo>> manualSlots() => _repo.manualSlots();
  Future<List<SlotInfo>> autosaves() => _repo.autosaves();

  /// Empties [slot]; not a game action, so [state] does not change.
  Future<void> deleteSlot(int slot) => _repo.deleteSlot(slot);

  /// [state] without a [Failed] wrapper.
  GameState get _settled => switch (_state) {
    Failed(:final previous) => previous,
    final s => s,
  };

  void _set(GameState s) {
    _state = s;
    notifyListeners();
  }

  /// Sets [Ready] for a game just started or loaded, under a new game id
  /// and without the old game's [pendingLineup].
  Future<void> _enterGame() {
    _gameId++;
    pendingLineup = null;
    return _refresh(null);
  }

  /// Fetches home and sets [Ready], reusing [previous]'s refs when it is
  /// [Ready] (refs are fixed per game) and fetching them otherwise. With
  /// [unlessBusy] (non-busy actions) nothing is set while a busy action
  /// started meanwhile runs: it refreshes when it ends.
  Future<void> _refresh(GameState? previous, {bool unlessBusy = false}) async {
    final home = await _gateway.home();
    final refs = previous is Ready ? previous.refs : await _gateway.refs();
    if (unlessBusy && _state is Busy) return;
    _set(Ready(home, refs, _gameId));
  }

  /// Autosaves and refreshes home after the world changed. When saving
  /// fails the world has still moved on, so home is refreshed anyway (the
  /// failure keeps it as previous) and [retry] only saves again, returning
  /// the kept [outcome].
  Future<void> _autosaveAfterMutation(
    GameState previous,
    AdvanceOutcome outcome,
  ) async {
    try {
      await _repo.autosave();
    } on Exception {
      _lastAction = () => _run('autosave', (p) async {
        await _repo.autosave();
        await _refresh(p);
        return outcome;
      });
      await _refresh(previous);
      rethrow;
    }
    await _refresh(previous);
  }

  /// Runs [body] with the settled state before it; [body] sets the final
  /// state. Errors set [Failed] over the settled state [body] reached
  /// ([previous] unless it set a new one). A non-busy action that fails
  /// while a busy one runs leaves the state to that action.
  Future<T?> _run<T>(
    String what,
    Future<T> Function(GameState previous) body, {
    bool busy = true,
  }) async {
    if (_state is Busy) throw StateError('busy');
    final previous = _settled;
    _lastAction = () => _run<T>(what, body, busy: busy);
    if (busy) _set(Busy(what));
    void fail(GatewayError e) {
      if (!busy && _state is Busy) return;
      _set(Failed(e, _state is Busy ? previous : _settled));
    }

    try {
      return await body(previous);
    } on GatewayError catch (e) {
      fail(e);
    } on SaveError catch (e) {
      fail(GatewayError(GatewayErrorKind.save, e.message, saveKind: e.kind));
    } catch (e) {
      fail(GatewayError(GatewayErrorKind.engine, '$e'));
      rethrow;
    }
    return null;
  }
}
