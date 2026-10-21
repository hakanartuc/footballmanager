import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User settings; call [load] once before reading [locale].
class SettingsController extends ChangeNotifier {
  static const _localeKey = 'locale';

  /// Null means follow the system locale.
  Locale? locale;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_localeKey);
    locale = code == null ? null : Locale(code);
  }

  Future<void> setLocale(Locale? value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.remove(_localeKey);
    } else {
      await prefs.setString(_localeKey, value.languageCode);
    }
    locale = value;
    notifyListeners();
  }
}
