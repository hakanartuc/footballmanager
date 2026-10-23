import 'package:cm_app/l10n/formatters.dart';
import 'package:cm_app/l10n/generated/app_localizations.dart';
import 'package:engine/engine.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

const _tr = Locale('tr');
const _en = Locale('en');

void main() {
  late AppLocalizations tr;
  late AppLocalizations en;

  setUpAll(() async {
    // In the app, the flutter_localizations delegates initialise this.
    await initializeDateFormatting('tr');
    await initializeDateFormatting('en');
    tr = await AppLocalizations.delegate.load(_tr);
    en = await AppLocalizations.delegate.load(_en);
  });

  test('formatDate', () {
    final d = GameDate.ymd(2026, 8, 8);
    expect(formatDate(d, _tr), '8 Ağu 2026');
    expect(formatDate(d, _en), 'Aug 8, 2026');
  });

  test('formationLabel', () {
    for (final (l, custom) in [(tr, 'Özel'), (en, 'Custom')]) {
      expect(
        {for (final f in Formation.values) f: formationLabel(f, l)},
        {
          Formation.f442: '4-4-2',
          Formation.f433: '4-3-3',
          Formation.f451: '4-5-1',
          Formation.f352: '3-5-2',
          Formation.f4231: '4-2-3-1',
          Formation.f532: '5-3-2',
          Formation.custom: custom,
        },
      );
    }
  });

  test('money', () {
    expect(money(1250000, _tr), '1.250.000');
    expect(money(1250000, _en), '1,250,000');
  });

  test('positionCode is locale-independent', () {
    expect(
      Position.values.map(positionCode).join(' '),
      'GK DL DC DR DM ML MC MR AML AMC AMR ST',
    );
  });

  test('attrGroupOf splits Attr into 9/9/7/5 contiguous groups', () {
    final groups = [for (final a in Attr.values) attrGroupOf(a)];
    expect(groups, [
      ...List.filled(9, AttrGroup.technical),
      ...List.filled(9, AttrGroup.mental),
      ...List.filled(7, AttrGroup.physical),
      ...List.filled(5, AttrGroup.goalkeeping),
    ]);
    expect(attrGroupOf(Attr.tackling), AttrGroup.technical);
    expect(attrGroupOf(Attr.decisions), AttrGroup.mental);
    expect(attrGroupOf(Attr.agility), AttrGroup.physical);
    expect(attrGroupOf(Attr.reflexes), AttrGroup.goalkeeping);
  });

  test('countryName', () {
    expect(countryName('TR', tr), 'Türkiye');
    expect(countryName('ENG', en), 'England');
    expect(countryName('XX', tr), 'XX');
  });

  test('enum names are non-empty and distinct per locale', () {
    for (final l in [tr, en]) {
      final lists = <List<String>>[
        [for (final p in Position.values) positionName(p, l)],
        [for (final a in Attr.values) attrName(a, l)],
        [for (final s in PlayerStatus.values) statusName(s, l)],
        [for (final e in LineupError.values) lineupErrorText(e, l)],
        [for (final s in WorldSize.values) worldSizeName(s, l)],
        [for (final g in AttrGroup.values) attrGroupName(g, l)],
      ];
      for (final names in lists) {
        expect(names.every((n) => n.isNotEmpty), isTrue);
        expect(names.toSet(), hasLength(names.length));
      }
    }
    expect(attrName(Attr.finishing, tr), 'Bitiricilik');
    expect(positionName(Position.gk, en), 'Goalkeeper');
  });
}
