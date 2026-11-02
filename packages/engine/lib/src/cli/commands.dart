import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';

import '../core/game_date.dart';
import '../gen/world_generator.dart';
import '../invariants/invariants.dart';
import '../model/events.dart';
import '../model/json.dart';
import '../model/match_result.dart';
import '../session/engine_session.dart';
import '../sim/new_game.dart';

/// Runs the `cm` command line with [args], writing results to [out] and
/// errors to [err] (default `stdout`/`stderr`).
///
/// Exit codes: 0 success, 1 failure (e.g. a bad save), 2 invariant
/// violation (`simulate --invariants`), 64 usage error.
Future<int> runCli(
  List<String> args, {
  StringSink? out,
  StringSink? err,
}) async {
  final o = out ?? stdout;
  final e = err ?? stderr;
  final runner = CommandRunner<int>('cm', 'Headless football-manager engine.')
    ..addCommand(_GenerateCommand(o))
    ..addCommand(_SimulateCommand(o, e))
    ..addCommand(_BenchCommand(o))
    ..addCommand(_InspectCommand(o));
  try {
    return await runner.run(args) ?? 0;
  } on UsageException catch (x) {
    e.writeln(x);
    return 64;
  } on Exception catch (x) {
    e.writeln(x);
    return 1;
  } on ArgumentError catch (x) {
    e.writeln(x);
    return 1;
  }
}

/// 0 when [violations] is empty; otherwise writes the first one as JSON
/// `{date, rule, detail}` to [err] and returns 2.
int violationExitCode(
  List<Violation> violations,
  GameDate date,
  StringSink err,
) {
  if (violations.isEmpty) return 0;
  final v = violations.first;
  err.writeln(
    jsonEncode({'date': date.iso, 'rule': v.rule, 'detail': v.detail}),
  );
  return 2;
}

const _pretty = JsonEncoder.withIndent('  ');

/// A command that starts a new unemployed game from `--seed` and `--size`.
abstract class _NewGameCommand extends Command<int> {
  _NewGameCommand() {
    argParser
      ..addOption('seed', defaultsTo: '1', help: 'World seed.')
      ..addOption(
        'size',
        defaultsTo: 'small',
        allowed: [for (final s in WorldSize.values) s.name],
      );
  }

  int intOption(String name) {
    final v = int.tryParse(argResults!.option(name) ?? '');
    if (v == null) usageException('--$name must be an integer.');
    return v;
  }

  EngineSession newSession() => EngineSession.newGame(
    NewGameSpec(
      seed: intOption('seed'),
      size: WorldSize.values.byName(argResults!.option('size')!),
      managerFirstName: 'CLI',
      managerLastName: 'Manager',
      managerCountryCode: 'TR',
      startClubId: null,
    ),
  );
}

class _GenerateCommand extends _NewGameCommand {
  _GenerateCommand(this.out) {
    argParser.addOption('out', help: 'Save file to write (required).');
  }

  final StringSink out;

  @override
  String get name => 'generate';
  @override
  String get description => 'Generate a world and write its save bytes.';

  @override
  int run() {
    final path = argResults!.option('out');
    if (path == null) usageException('--out is required.');
    final watch = Stopwatch()..start();
    final session = newSession();
    final generateMs = watch.elapsedMilliseconds;
    final bytes = session.save();
    File(path).writeAsBytesSync(bytes);
    final w = session.world;
    out.writeln(
      jsonEncode({
        'countries': w.countries.length,
        'leagues': w.leagues.length,
        'clubs': w.clubs.length,
        'players': w.players.length,
        'fixtures': w.fixtures.length,
        'bytes': bytes.length,
        'generateMs': generateMs,
      }),
    );
    return 0;
  }
}

class _SimulateCommand extends _NewGameCommand {
  _SimulateCommand(this.out, this.err) {
    argParser
      ..addOption('seasons', defaultsTo: '1')
      ..addFlag('invariants', help: 'Check invariants after every day.')
      ..addOption('report', help: 'Also write the JSON report here.');
  }

  final StringSink out;
  final StringSink err;

  @override
  String get name => 'simulate';
  @override
  String get description => 'Simulate whole seasons with an unemployed user.';

  @override
  int run() {
    final seasons = intOption('seasons');
    final check = argResults!.flag('invariants');
    final session = newSession();
    final w = session.world;
    final report = <Map<String, Object?>>[];
    for (var i = 0; i < seasons; i++) {
      final year = w.seasonYear;
      final watch = Stopwatch()..start();
      var days = 0;
      while (true) {
        final summary = session.advanceDay();
        days++;
        if (check) {
          final code = violationExitCode(
            session.checkInvariants(),
            summary.date,
            err,
          );
          if (code != 0) return code;
        }
        if (summary.events.any((e) => e is SeasonEnded)) break;
      }
      final played = [
        for (final f in w.fixtures.values)
          if (f.seasonYear == year && f.result != null) f.result!,
      ];
      final n = played.length;
      final goals = played.fold(0, (s, r) => s + r.homeGoals + r.awayGoals);
      double pct(bool Function(int h, int a) p) => n == 0
          ? 0
          : 100 * played.where((r) => p(r.homeGoals, r.awayGoals)).length / n;
      int count(bool Function(MatchEvent e) p) =>
          played.fold(0, (s, r) => s + r.events.where(p).length);
      report.add({
        'seasonYear': year,
        'champions': {
          for (final e in w.history.last.champions.entries)
            w.leagues[e.key]!.name: w.clubs[e.value]!.name,
        },
        'matches': n,
        'goals': goals,
        'goalsPerMatch': n == 0 ? 0 : goals / n,
        'homeWinPct': pct((h, a) => h > a),
        'drawPct': pct((h, a) => h == a),
        'awayWinPct': pct((h, a) => h < a),
        'yellows': count((e) => e is Booking && e.kind == CardKind.yellow),
        'reds': count((e) => e is Booking && e.kind != CardKind.yellow),
        'injuries': count((e) => e is Injury),
        'substitutions': count((e) => e is Substitution),
        'violations': 0,
        'days': days,
        'msTotal': watch.elapsedMilliseconds,
      });
    }
    final json = _pretty.convert(report);
    out.writeln(json);
    final path = argResults!.option('report');
    if (path != null) File(path).writeAsStringSync(json);
    return 0;
  }
}

class _BenchCommand extends _NewGameCommand {
  _BenchCommand(this.out) {
    argParser
      ..addOption('days', defaultsTo: '400')
      ..addOption('report', help: 'Also write the JSON report here.');
  }

  final StringSink out;

  @override
  String get name => 'bench';
  @override
  String get description => 'Time generation, days, save and load.';

  @override
  int run() {
    final days = intOption('days');
    final watch = Stopwatch()..start();
    final session = newSession();
    final generateMs = watch.elapsedMilliseconds;
    final matchDays = <double>[];
    final otherDays = <double>[];
    for (var i = 0; i < days; i++) {
      final s = session.advanceDay();
      (s.playedFixtures.isNotEmpty ? matchDays : otherDays).add(
        s.elapsed.inMicroseconds / 1000,
      );
    }
    watch.reset();
    final bytes = session.save();
    final saveMs = watch.elapsedMilliseconds;
    watch.reset();
    EngineSession.fromBytes(bytes);
    final loadMs = watch.elapsedMilliseconds;
    final json = _pretty.convert({
      'generateMs': generateMs,
      'days': days,
      'matchDays': _stats(matchDays),
      'otherDays': _stats(otherDays),
      'saveBytes': bytes.length,
      'saveMs': saveMs,
      'loadMs': loadMs,
    });
    out.writeln(json);
    final path = argResults!.option('report');
    if (path != null) File(path).writeAsStringSync(json);
    return 0;
  }

  static Map<String, num> _stats(List<double> ms) {
    final s = [...ms]..sort();
    double at(int p) => s.isEmpty ? 0 : s[((p / 100) * (s.length - 1)).round()];
    return {
      'count': s.length,
      'p50Ms': at(50),
      'p95Ms': at(95),
      'maxMs': s.isEmpty ? 0 : s.last,
    };
  }
}

class _InspectCommand extends Command<int> {
  _InspectCommand(this.out) {
    argParser
      ..addOption('club', help: 'Club id.')
      ..addOption('table', help: 'League id.')
      ..addFlag('summary', negatable: false);
  }

  final StringSink out;

  @override
  String get name => 'inspect';
  @override
  String get description => 'Print a club, a league table or a summary.';
  @override
  String get invocation =>
      'cm inspect <save.bin> '
      '(--club <id> | --table <leagueId> | --summary)';

  @override
  int run() {
    final a = argResults!;
    if (a.rest.length != 1) usageException('Expected one save file.');
    final views = [
      a.wasParsed('club'),
      a.wasParsed('table'),
      a.flag('summary'),
    ].where((v) => v).length;
    if (views != 1) {
      usageException('Give exactly one of --club, --table, --summary.');
    }
    int idOption(String name) =>
        int.tryParse(a.option(name)!) ??
        usageException('--$name must be an integer.');
    final clubId = a.wasParsed('club') ? idOption('club') : null;
    final leagueId = a.wasParsed('table') ? idOption('table') : null;

    final session = EngineSession.fromBytes(
      Uint8List.fromList(File(a.rest.single).readAsBytesSync()),
    );
    final w = session.world;
    final Object json;
    if (clubId != null) {
      final club = w.clubs[clubId];
      if (club == null) throw ArgumentError.value(clubId, 'club', 'no such');
      json = {
        'club': clubToJson(club),
        'squad': [
          for (final p in session.squad(clubId))
            {
              'id': p.id,
              'name': '${p.firstName} ${p.lastName}',
              'position': p.mainPosition.name,
              'age': p.ageAt(w.date),
              'ca': p.ca,
            },
        ],
      };
    } else if (leagueId != null) {
      if (!w.leagues.containsKey(leagueId)) {
        throw ArgumentError.value(leagueId, 'table', 'no such league');
      }
      json = [
        for (final r in session.table(leagueId))
          {
            'clubId': r.clubId,
            'clubName': w.clubs[r.clubId]!.name,
            'played': r.played,
            'won': r.won,
            'drawn': r.drawn,
            'lost': r.lost,
            'gf': r.gf,
            'ga': r.ga,
            'gd': r.gd,
            'points': r.points,
          },
      ];
    } else {
      final m = w.managers[w.userManagerId]!;
      json = {
        'date': w.date.iso,
        'seasonYear': w.seasonYear,
        'countries': w.countries.length,
        'clubs': w.clubs.length,
        'players': w.players.length,
        'userManager': '${m.firstName} ${m.lastName}',
      };
    }
    out.writeln(_pretty.convert(json));
    return 0;
  }
}
