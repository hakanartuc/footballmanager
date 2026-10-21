import 'dart:convert';
import 'dart:io';

import 'package:cm_app/engine/snapshots.dart';
import 'package:cm_app/l10n/event_text.dart';
import 'package:cm_app/l10n/generated/app_localizations.dart';
import 'package:engine/engine.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

final _date = GameDate.ymd(2026, 8, 8);

InboxItem _item(GameEvent event, InboxLabels labels) =>
    InboxItem(id: 1, date: _date, read: false, event: event, labels: labels);

/// One item per [GameEvent] subtype, with the strings the text must contain.
final _cases = <String, (InboxItem, List<String>)>{
  'MatchPlayed': (
    _item(
      MatchPlayed(date: _date, fixtureId: 7),
      const InboxLabels(
        homeName: 'Galatasaray',
        awayName: 'Fenerbahçe',
        homeGoals: 3,
        awayGoals: 1,
      ),
    ),
    ['Galatasaray 3 - 1 Fenerbahçe'],
  ),
  'SeasonEnded': (
    _item(SeasonEnded(date: _date, seasonYear: 2026), const InboxLabels()),
    ['2026'],
  ),
  'LeagueChampion': (
    _item(
      LeagueChampion(date: _date, leagueId: 1, clubId: 2),
      const InboxLabels(clubName: 'Beşiktaş', leagueName: 'Süper Lig'),
    ),
    ['Beşiktaş', 'Süper Lig'],
  ),
  'Promoted': (
    _item(
      Promoted(date: _date, clubId: 2, fromLeagueId: 2, toLeagueId: 1),
      const InboxLabels(
        clubName: 'Göztepe',
        leagueName: '1. Lig',
        toLeagueName: 'Süper Lig',
      ),
    ),
    ['Göztepe', '1. Lig', 'Süper Lig'],
  ),
  'Relegated': (
    _item(
      Relegated(date: _date, clubId: 2, fromLeagueId: 1, toLeagueId: 2),
      const InboxLabels(
        clubName: 'Ankaragücü',
        leagueName: 'Süper Lig',
        toLeagueName: '1. Lig',
      ),
    ),
    ['Ankaragücü', 'Süper Lig', '1. Lig'],
  ),
  'PlayerRetired': (
    _item(
      PlayerRetired(date: _date, playerId: 9, clubId: 2),
      const InboxLabels(clubName: 'Trabzonspor', playerNames: ['Ali Yılmaz']),
    ),
    ['Ali Yılmaz', 'Trabzonspor'],
  ),
  'YouthIntake': (
    _item(
      YouthIntake(date: _date, clubId: 2, playerIds: [10, 11]),
      const InboxLabels(
        clubName: 'Bursaspor',
        playerNames: ['Can Demir', 'Efe Kaya'],
      ),
    ),
    ['2', 'Bursaspor', 'Can Demir', 'Efe Kaya'],
  ),
  'YouthReleased': (
    _item(
      YouthReleased(date: _date, clubId: 2, playerIds: [10, 11, 12]),
      const InboxLabels(clubName: 'Sivasspor'),
    ),
    ['3', 'Sivasspor'],
  ),
  'NewSeasonStarted': (
    _item(NewSeasonStarted(date: _date, seasonYear: 2027), const InboxLabels()),
    ['2027'],
  ),
};

Set<String> _messageKeys(String file) {
  final json = jsonDecode(File('lib/l10n/$file').readAsStringSync()) as Map;
  return {
    for (final k in json.keys.cast<String>())
      if (!k.startsWith('@')) k,
  };
}

void main() {
  for (final code in ['tr', 'en']) {
    group('describe ($code)', () {
      late AppLocalizations l;
      setUpAll(() async {
        l = await AppLocalizations.delegate.load(Locale(code));
      });

      for (final MapEntry(key: name, value: (item, expected))
          in _cases.entries) {
        test(name, () {
          final r = EventText.describe(item, l);
          final text = '${r.title}\n${r.body}';
          for (final s in expected) {
            expect(text, contains(s));
          }
          expect(r.title, isNotEmpty);
          expect(r.body, isNotEmpty);
          expect(text, isNot(contains('{')));
          expect(text, isNot(contains('null')));
        });
      }

      test('PlayerRetired without a resolvable name', () {
        final r = EventText.describe(
          _item(
            PlayerRetired(date: _date, playerId: 9, clubId: 2),
            const InboxLabels(clubName: 'Trabzonspor'),
          ),
          l,
        );
        final text = '${r.title}\n${r.body}';
        expect(text, contains('Trabzonspor'));
        expect(text, isNot(contains('null')));
        expect(text, isNot(contains('{')));
      });

      test('PlayerRetired as a free agent', () {
        final r = EventText.describe(
          _item(
            PlayerRetired(date: _date, playerId: 9, clubId: null),
            const InboxLabels(),
          ),
          l,
        );
        final text = '${r.title}\n${r.body}';
        expect(text, isNot(contains('null')));
        expect(text, isNot(contains('{')));
      });

      test('YouthIntake whose players are all gone', () {
        final r = EventText.describe(
          _item(
            YouthIntake(date: _date, clubId: 2, playerIds: [10]),
            const InboxLabels(clubName: 'Bursaspor'),
          ),
          l,
        );
        expect('${r.title}\n${r.body}', contains('Bursaspor'));
      });
    });
  }

  test('Turkish champion title reads naturally', () async {
    final l = await AppLocalizations.delegate.load(const Locale('tr'));
    final r = EventText.describe(_cases['LeagueChampion']!.$1, l);
    expect(r.title, 'Beşiktaş, Süper Lig şampiyonu oldu');
  });

  test('ARB files have identical key sets', () {
    final en = _messageKeys('app_en.arb');
    final tr = _messageKeys('app_tr.arb');
    expect(tr.difference(en), isEmpty, reason: 'only in tr');
    expect(en.difference(tr), isEmpty, reason: 'only in en');
  });
}
