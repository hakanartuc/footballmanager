import 'package:cm_app/data/settings_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('absent key means system locale', () async {
    final c = SettingsController();
    await c.load();
    expect(c.locale, isNull);
  });

  test('setLocale persists, notifies and survives a reload', () async {
    final c = SettingsController();
    await c.load();
    var notified = 0;
    c.addListener(() => notified++);

    await c.setLocale(const Locale('en'));
    expect(c.locale, const Locale('en'));
    expect(notified, 1);

    final reloaded = SettingsController();
    await reloaded.load();
    expect(reloaded.locale, const Locale('en'));
  });

  test('load reads a stored value', () async {
    SharedPreferences.setMockInitialValues({'locale': 'tr'});
    final c = SettingsController();
    await c.load();
    expect(c.locale, const Locale('tr'));
  });

  test('setLocale(null) removes the key', () async {
    final c = SettingsController();
    await c.load();
    await c.setLocale(const Locale('tr'));
    await c.setLocale(null);
    expect(c.locale, isNull);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('locale'), isFalse);
  });
}
