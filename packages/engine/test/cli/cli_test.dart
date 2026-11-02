import 'dart:convert';
import 'dart:io';

import 'package:engine/engine.dart';
import 'package:engine/src/cli/commands.dart';
import 'package:test/test.dart';

/// Runs the CLI in-process with captured sinks.
Future<(int, String, String)> _run(List<String> args) async {
  final out = StringBuffer();
  final err = StringBuffer();
  final code = await runCli(args, out: out, err: err);
  return (code, out.toString(), err.toString());
}

void main() {
  late Directory tmp;
  late String savePath;
  late Map<String, dynamic> generated;

  setUpAll(() async {
    tmp = Directory.systemTemp.createTempSync('cm_cli_test');
    savePath = '${tmp.path}/world.bin';
    final (code, out, err) = await _run([
      'generate',
      '--seed',
      '1',
      '--size',
      'small',
      '--out',
      savePath,
    ]);
    expect(code, 0, reason: err);
    generated = jsonDecode(out) as Map<String, dynamic>;
  });

  tearDownAll(() => tmp.deleteSync(recursive: true));

  test('generate writes the save and prints its counts', () {
    expect(generated.keys, {
      'countries',
      'leagues',
      'clubs',
      'players',
      'fixtures',
      'bytes',
      'generateMs',
    });
    expect(generated['countries'], WorldSize.small.countryCount);
    expect(generated['clubs'] as int, greaterThan(0));
    expect(generated['players'] as int, greaterThan(generated['clubs'] as int));
    expect(generated['bytes'], File(savePath).lengthSync());
  });

  test(
    'simulate one season with invariants reports one clean season',
    () async {
      final reportPath = '${tmp.path}/r.json';
      final (code, out, err) = await _run([
        'simulate',
        '--seed',
        '1',
        '--size',
        'small',
        '--seasons',
        '1',
        '--invariants',
        '--report',
        reportPath,
      ]);
      expect(code, 0, reason: err);
      expect(err, isEmpty);
      final report = jsonDecode(File(reportPath).readAsStringSync()) as List;
      expect(jsonDecode(out), report);
      expect(report, hasLength(1));
      final season = report.single as Map<String, dynamic>;
      expect(season['seasonYear'], 2026);
      expect(season['violations'], 0);
      expect(season['goalsPerMatch'] as num, inInclusiveRange(2.0, 3.5));
      expect(season['matches'] as int, greaterThan(0));
      final matches = season['matches'] as int;
      for (final key in ['yellows', 'reds', 'injuries', 'substitutions']) {
        expect(season[key], isA<int>(), reason: key);
      }
      expect(season['yellows'] as int, greaterThanOrEqualTo(2.5 * matches));
      expect(season['reds'] as int, greaterThanOrEqualTo(0.1 * matches));
      expect(season['injuries'] as int, greaterThan(0));
      expect(season['substitutions'] as int, greaterThan(matches));
      final pct =
          (season['homeWinPct'] as num) +
          (season['drawPct'] as num) +
          (season['awayWinPct'] as num);
      expect(pct, closeTo(100, 1e-6));
      expect(
        (season['champions'] as Map).length,
        generated['leagues'],
        reason: 'one champion per league',
      );
      expect(season['days'] as int, greaterThan(300));
    },
  );

  test('calibrate prints the table and writes the JSON report', () async {
    final reportPath = '${tmp.path}/c.json';
    final (code, out, err) = await _run([
      'calibrate',
      '--seed',
      '3',
      '--matches',
      '50',
      '--report',
      reportPath,
    ]);
    expect(code, 0, reason: err);
    expect(out, contains('calibration: 50 matches, seed 3'));
    expect(out, contains('goals/match'));
    final report =
        jsonDecode(File(reportPath).readAsStringSync()) as Map<String, dynamic>;
    expect(report.keys, {
      'matches',
      'seed',
      'homeAttr',
      'awayAttr',
      'goalsPerMatch',
      'homeWinPct',
      'drawPct',
      'awayWinPct',
      'homeShots',
      'awayShots',
      'homeOnTarget',
      'awayOnTarget',
      'corners',
      'fouls',
      'yellows',
      'reds',
      'injuries',
      'substitutions',
      'scorePct',
      'fivePlusGoalsPct',
      'homePossessionPct',
      'homeXg',
      'awayXg',
      'addedTimePerHalf',
    });
    expect(report['matches'], 50);
    final pct =
        (report['homeWinPct'] as num) +
        (report['drawPct'] as num) +
        (report['awayWinPct'] as num);
    expect(pct, closeTo(100, 1e-6));
    expect(report['scorePct'], isA<Map<String, dynamic>>());
  });

  test('calibrate --gap and --season write their reports', () async {
    final gapPath = '${tmp.path}/g.json';
    final (gapCode, gapOut, gapErr) = await _run([
      'calibrate',
      '--seed',
      '3',
      '--matches',
      '20',
      '--gap',
      '20',
      '--report',
      gapPath,
    ]);
    expect(gapCode, 0, reason: gapErr);
    expect(gapOut, contains('gap +20 CA'));
    final gap = jsonDecode(File(gapPath).readAsStringSync()) as Map;
    expect(gap['gap'], 20);
    expect(gap['matches'], 20);
    expect(
      (gap['strongWinPct'] as num) +
          (gap['drawPct'] as num) +
          (gap['weakWinPct'] as num),
      closeTo(100, 1e-6),
    );

    final seasonPath = '${tmp.path}/s.json';
    final (seasonCode, seasonOut, seasonErr) = await _run([
      'calibrate',
      '--seed',
      '3',
      '--season',
      '--seasons',
      '1',
      '--report',
      seasonPath,
    ]);
    expect(seasonCode, 0, reason: seasonErr);
    expect(seasonOut, contains('season calibration: 1 seasons'));
    final season = jsonDecode(File(seasonPath).readAsStringSync()) as Map;
    expect(season['seasons'], 1);
    expect(season['perSeason'], hasLength(1));
    expect((await _run(['calibrate', '--gap', '15'])).$1, 64);
  });

  test('bench writes a report with every key', () async {
    final reportPath = '${tmp.path}/b.json';
    final (code, out, err) = await _run([
      'bench',
      '--seed',
      '1',
      '--size',
      'small',
      '--days',
      '30',
      '--report',
      reportPath,
    ]);
    expect(code, 0, reason: err);
    final report =
        jsonDecode(File(reportPath).readAsStringSync()) as Map<String, dynamic>;
    expect(jsonDecode(out), report);
    expect(report.keys, {
      'generateMs',
      'days',
      'matchDays',
      'otherDays',
      'saveBytes',
      'saveMs',
      'loadMs',
    });
    expect(report['days'], 30);
    final match = report['matchDays'] as Map<String, dynamic>;
    final other = report['otherDays'] as Map<String, dynamic>;
    for (final m in [match, other]) {
      expect(m.keys, {'count', 'p50Ms', 'p95Ms', 'maxMs'});
    }
    expect((match['count'] as int) + (other['count'] as int), 30);
    expect(match['count'] as int, greaterThan(0));
    expect(report['saveBytes'] as int, greaterThan(0));
  });

  group('inspect', () {
    test('--summary prints the season year and counts', () async {
      final (code, out, err) = await _run(['inspect', savePath, '--summary']);
      expect(code, 0, reason: err);
      final s = jsonDecode(out) as Map<String, dynamic>;
      expect(s['seasonYear'], 2026);
      expect(s['clubs'], generated['clubs']);
      expect(s['players'], generated['players']);
      expect(s['countries'], generated['countries']);
      expect(s['userManager'], 'CLI Manager');
    });

    test('--table prints one row per club of the league', () async {
      final world = EngineSession.fromBytes(
        File(savePath).readAsBytesSync(),
      ).world;
      final league = world.leagues.values.first;
      final (code, out, err) = await _run([
        'inspect',
        savePath,
        '--table',
        '${league.id}',
      ]);
      expect(code, 0, reason: err);
      final rows = jsonDecode(out) as List;
      expect(rows, hasLength(league.clubIds.length));
      expect((rows.first as Map).keys, {
        'clubId',
        'clubName',
        'played',
        'won',
        'drawn',
        'lost',
        'gf',
        'ga',
        'gd',
        'points',
      });
      expect(
        rows.map((r) => (r as Map)['clubId']).toSet(),
        league.clubIds.toSet(),
      );
    });

    test('--club prints the club and its squad', () async {
      final world = EngineSession.fromBytes(
        File(savePath).readAsBytesSync(),
      ).world;
      final club = world.clubs.values.first;
      final (code, out, err) = await _run([
        'inspect',
        savePath,
        '--club',
        '${club.id}',
      ]);
      expect(code, 0, reason: err);
      final j = jsonDecode(out) as Map<String, dynamic>;
      expect((j['club'] as Map)['name'], club.name);
      final squad = j['squad'] as List;
      expect(squad, hasLength(world.squadOf(club.id).length));
      expect((squad.first as Map).keys, {
        'id',
        'name',
        'position',
        'age',
        'ca',
      });
    });

    test('without exactly one view is a usage error', () async {
      expect((await _run(['inspect', savePath])).$1, 64);
      expect(
        (await _run(['inspect', savePath, '--summary', '--table', '1'])).$1,
        64,
      );
    });

    test('an unknown club or league fails with a message', () async {
      for (final view in ['--club', '--table']) {
        final (code, out, err) = await _run(['inspect', savePath, view, '-1']);
        expect(code, 1, reason: view);
        expect(out, isEmpty);
        expect(err, contains('no such'));
      }
    });

    test('a missing file fails with a message', () async {
      final (code, out, err) = await _run([
        'inspect',
        '${tmp.path}/nope.bin',
        '--summary',
      ]);
      expect(code, 1);
      expect(out, isEmpty);
      expect(err, isNotEmpty);
    });

    test('a garbage file fails with a message', () async {
      final path = '${tmp.path}/garbage.bin';
      File(path).writeAsBytesSync([1, 2, 3, 4, 5]);
      final (code, out, err) = await _run(['inspect', path, '--summary']);
      expect(code, 1);
      expect(out, isEmpty);
      expect(err, contains('SaveError'));
    });
  });

  group('usage errors return 64', () {
    test('unknown command', () async {
      final (code, out, err) = await _run(['frobnicate']);
      expect(code, 64);
      expect(out, isEmpty);
      expect(err, isNotEmpty);
    });

    test('bad option values', () async {
      expect((await _run(['generate', '--seed', 'x', '--out', 'a'])).$1, 64);
      expect((await _run(['generate', '--size', 'huge', '--out', 'a'])).$1, 64);
      expect((await _run(['generate', '--seed', '1'])).$1, 64);
    });
  });

  group('violationExitCode', () {
    final date = GameDate.ymd(2026, 9, 1);

    test('is 0 and silent for no violations', () {
      final err = StringBuffer();
      expect(violationExitCode(const [], date, err), 0);
      expect(err.toString(), isEmpty);
    });

    test('is 2 and prints the first violation as JSON', () {
      final err = StringBuffer();
      final code = violationExitCode(
        const [Violation('squadSize', 'club 3 has 10'), Violation('b', 'c')],
        date,
        err,
      );
      expect(code, 2);
      expect(jsonDecode(err.toString()), {
        'date': '2026-09-01',
        'rule': 'squadSize',
        'detail': 'club 3 has 10',
      });
    });
  });
}
