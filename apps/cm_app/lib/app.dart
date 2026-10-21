import 'package:flutter/material.dart';

import 'l10n/generated/app_localizations.dart';

class CmApp extends StatelessWidget {
  const CmApp({super.key, this.locale, this.gateway, this.store});

  final Locale? locale;

  // Placeholders: typed `Object?` until the engine gateway and save store
  // exist; they will be retyped to `EngineGateway?` / `SaveStore?` without
  // changing call sites.
  final Object? gateway;
  final Object? store;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      onGenerateTitle: (c) => AppLocalizations.of(c)!.appTitle,
      home: const _Home(),
    );
  }
}

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(child: Text(AppLocalizations.of(context)!.appTitle)),
    );
  }
}
