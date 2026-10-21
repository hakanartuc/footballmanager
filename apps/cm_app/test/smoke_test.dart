import 'package:cm_app/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows app title in Turkish and English', (tester) async {
    await tester.pumpWidget(const CmApp(locale: Locale('tr')));
    await tester.pumpAndSettle();
    expect(find.text('Futbol Menajeri'), findsOneWidget);

    await tester.pumpWidget(const CmApp(locale: Locale('en')));
    await tester.pumpAndSettle();
    expect(find.text('Football Manager'), findsOneWidget);
  });
}
