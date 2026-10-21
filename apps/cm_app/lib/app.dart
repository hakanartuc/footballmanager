import 'dart:async';

import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/app_save_store.dart';
import 'data/entitlements.dart';
import 'data/game_repository.dart';
import 'data/settings_controller.dart';
import 'engine/engine_gateway.dart';
import 'engine/isolate_gateway.dart';
import 'l10n/generated/app_localizations.dart';
import 'state/game_controller.dart';
import 'ui/saves/saves_screen.dart';
import 'ui/shell/game_shell.dart';
import 'ui/start/start_screen.dart';
import 'ui/theme.dart';
import 'ui/widgets/busy_overlay.dart';
import 'ui/widgets/error_card.dart';

class CmApp extends StatelessWidget {
  const CmApp({
    super.key,
    this.locale,
    this.gateway,
    this.store,
    this.settings,
    this.entitlements = Entitlements.dev,
    this.themeMode = ThemeMode.system,
  });

  final Locale? locale;

  /// Null creates an [IsolateGateway].
  final EngineGateway? gateway;

  /// Null opens the [AppSaveStore].
  final SaveStore? store;

  /// Null creates one; either way it is loaded at startup.
  final SettingsController? settings;
  final Entitlements entitlements;

  /// Fixed in golden tests; the platform brightness otherwise.
  final ThemeMode themeMode;

  @override
  Widget build(BuildContext context) => _AppBootstrap(app: this);
}

/// Creates whatever [CmApp] was not given, then provides the app state.
class _AppBootstrap extends StatefulWidget {
  const _AppBootstrap({required this.app});

  final CmApp app;

  @override
  State<_AppBootstrap> createState() => _AppBootstrapState();
}

typedef _Deps = (EngineGateway, SaveStore, SettingsController);

class _AppBootstrapState extends State<_AppBootstrap> {
  late Future<_Deps> _deps = _resolve();
  EngineGateway? _ownGateway;

  Future<_Deps> _resolve() async {
    final app = widget.app;
    final gateway = app.gateway ?? (_ownGateway = await IsolateGateway.spawn());
    final store = app.store ?? await AppSaveStore.open();
    final settings = app.settings ?? SettingsController();
    await settings.load();
    return (gateway, store, settings);
  }

  @override
  void dispose() {
    _ownGateway?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _deps,
      builder: (context, snap) {
        if (snap.hasError) {
          return _plainApp(
            ErrorCard(
              error: GatewayError(GatewayErrorKind.engine, '${snap.error}'),
              onRetry: () => setState(() => _deps = _resolve()),
            ),
          );
        }
        final deps = snap.data;
        if (deps == null) {
          return _plainApp(const CircularProgressIndicator());
        }
        final (gateway, store, settings) = deps;
        return MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: settings),
            ChangeNotifierProvider(
              create: (_) =>
                  GameController(GameRepository(gateway, store), gateway),
            ),
            Provider.value(value: widget.app.entitlements),
          ],
          child: Consumer<SettingsController>(
            builder: (context, settings, _) => MaterialApp(
              theme: lightTheme(),
              darkTheme: darkTheme(),
              themeMode: widget.app.themeMode,
              locale: settings.locale ?? widget.app.locale,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              onGenerateTitle: (c) => AppLocalizations.of(c)!.appTitle,
              home: const _Root(),
            ),
          ),
        );
      },
    );
  }

  /// [child] centred in a themed, localized app, for before the
  /// dependencies resolve.
  Widget _plainApp(Widget child) => MaterialApp(
    theme: lightTheme(),
    darkTheme: darkTheme(),
    themeMode: widget.app.themeMode,
    locale: widget.app.locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    onGenerateTitle: (c) => AppLocalizations.of(c)!.appTitle,
    home: Scaffold(body: Center(child: child)),
  );
}

/// Renders the [GameController] state.
class _Root extends StatefulWidget {
  const _Root();

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  /// The last [NoGame] or [Ready], shown under [Busy].
  GameState _settled = const NoGame();

  /// A second tap while the retry runs is ignored.
  Future<void> _retry(GameController controller) async {
    try {
      await controller.retry();
    } on StateError catch (e) {
      if (e.message != 'busy') rethrow;
    }
  }

  Widget _content(GameState s) => switch (s) {
    // Keyed per game so the tabs' state does not outlive the game it is for.
    Ready(:final home, :final gameId) => GameShell(
      key: ValueKey(gameId),
      home: home,
    ),
    _ => StartScreen(
      onLoadGame: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const SavesScreen(canSave: false),
        ),
      ),
    ),
  };

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<GameController>();
    final state = controller.state;
    if (state is NoGame || state is Ready) _settled = state;
    final shown = state is Failed ? state.previous : _settled;
    // One tree shape for every state so the content keeps its own state.
    return Stack(
      children: [
        BusyOverlay(busy: state is Busy, child: _content(shown)),
        if (state is Failed) ...[
          const ModalBarrier(color: Colors.black38, dismissible: false),
          Center(
            child: ErrorCard(
              error: state.error,
              onRetry: () => unawaited(_retry(controller)),
              onDismiss: controller.dismissError,
            ),
          ),
        ],
      ],
    );
  }
}
