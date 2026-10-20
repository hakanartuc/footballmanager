import 'dart:io';

import 'package:engine/engine.dart';
import 'package:engine/src/data/assets_embedded.dart';
import 'package:test/test.dart';

const _order = [
  'TR', 'ENG', 'ES', 'DE', 'IT', 'FR', 'NL', 'PT', //
  'BR', 'AR', 'US', 'MX', 'JP', 'KR', 'NG', 'AU',
];

/// Real top-flight club cities that must not appear in any city name.
const _realCities = [
  // TR
  'İstanbul', 'Istanbul', 'Ankara', 'İzmir', 'Izmir', 'Trabzon', 'Bursa',
  'Konya', 'Antalya', 'Adana',
  // ENG
  'Manchester', 'Liverpool', 'London', 'Leeds', 'Newcastle', 'Birmingham',
  'Sheffield', 'Everton',
  // ES
  'Madrid', 'Barcelona', 'Sevilla', 'Valencia', 'Bilbao',
  // DE
  'München', 'Dortmund', 'Berlin', 'Hamburg', 'Leipzig',
  // IT
  'Milano', 'Torino', 'Roma', 'Napoli',
  // FR
  'Paris', 'Marseille', 'Lyon', 'Lille',
];

void main() {
  final data = CountryData.load();

  test('loads 16 countries in world-size order with unique codes', () {
    expect([for (final c in data.countries) c.code], _order);
  });

  test('validate() finds no problems', () {
    expect(data.validate(), isEmpty);
  });

  test('every country references an existing pool', () {
    for (final c in data.countries) {
      expect(data.pools, contains(c.namePool), reason: c.code);
    }
    expect(data.pools.keys.toSet(), {
      for (final c in data.countries) c.namePool,
    });
  });

  test('tier sizes match the design', () {
    final sizes = {
      for (final c in data.countries)
        c.code: [for (final t in c.tiers) t.clubs],
    };
    expect(sizes, {
      'TR': [18, 18],
      'ENG': [20, 24],
      'ES': [20, 22],
      'DE': [18, 18],
      'IT': [20, 20],
      'FR': [18, 20],
      'NL': [18, 20],
      'PT': [18, 18],
      'BR': [20, 20],
      'AR': [28],
      'US': [24],
      'MX': [18],
      'JP': [20, 22],
      'KR': [12],
      'NG': [20],
      'AU': [12],
    });
  });

  test('reputations are within 1..100', () {
    for (final c in data.countries) {
      expect(c.reputation, inInclusiveRange(1, 100), reason: c.code);
    }
  });

  test('club and stadium patterns all contain {City}', () {
    data.pools.forEach((name, p) {
      for (final s in [...p.clubSuffixes, ...p.stadiumPatterns]) {
        expect(s, contains('{City}'), reason: '$name: $s');
      }
    });
  });

  test('no city name contains a real top-flight club city', () {
    data.pools.forEach((name, p) {
      for (final city in p.cityNames) {
        for (final real in _realCities) {
          expect(
            city.toLowerCase().contains(real.toLowerCase()),
            isFalse,
            reason: '$name: "$city" contains "$real"',
          );
        }
      }
    });
  });

  test('pool entries are unique within each list', () {
    data.pools.forEach((name, p) {
      for (final list in [p.firstNames, p.lastNames, p.cityNames]) {
        expect(list.toSet().length, list.length, reason: name);
      }
    });
  });

  test('validate() reports broken tiers, pools and duplicate codes', () {
    final broken = CountryData.load();
    final tr = broken.countries.first;
    tr.tiers.first.promoted = 1;
    tr.tiers.last.relegated = 2;
    tr.tiers.last.promoted = 4;
    tr.tiers.last.clubs = 10;
    broken.countries[1].code = 'TR';
    broken.countries[2].namePool = 'nope';
    broken.pools['tr']!.firstNames.length = 59;
    broken.pools['tr']!.stadiumPatterns.clear();

    final problems = broken.validate().join('\n');
    expect(problems, contains('TR tier1: promoted'));
    expect(problems, contains('TR tier2: relegated'));
    expect(problems, contains('TR tier2: promoted 4'));
    expect(problems, contains('TR tier2: 10 clubs'));
    expect(problems, contains('duplicate country code TR'));
    expect(problems, contains('ES: missing name pool "nope"'));
    expect(problems, contains('pool tr: firstNames'));
    expect(problems, contains('pool tr: stadiumPatterns'));
  });

  test('embedded assets are in sync with the JSON sources', () {
    final dir = Directory('lib/src/data/assets');
    final sources = {
      for (final f in dir.listSync(recursive: true).whereType<File>())
        if (f.path.endsWith('.json'))
          f.path
              .substring(dir.path.length + 1)
              .replaceAll(Platform.pathSeparator, '/'): f
              .readAsStringSync(),
    };
    expect(sources, hasLength(17));
    expect(
      embeddedAssets,
      sources,
      reason: 'run: dart run tool/embed_assets.dart',
    );
  });
}
