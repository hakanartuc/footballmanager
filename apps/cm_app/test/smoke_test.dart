import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pump_app.dart';

void main() {
  testWidgets('app title follows the locale', (tester) async {
    for (final locale in const [Locale('tr'), Locale('en')]) {
      final l = await loadL10n(locale);
      await pumpApp(tester, locale: locale, startReady: false);
      expect(tester.widget<Title>(find.byType(Title)).title, l.appTitle);
    }
  });
}
