import 'dart:async';

import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/formatters.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../state/game_controller.dart';
import '../settings/settings_screen.dart';
import 'new_game_screen.dart';

/// The screen without a game: continue the newest autosave, start a new
/// game or, with [onLoadGame], load a save.
class StartScreen extends StatefulWidget {
  const StartScreen({super.key, this.onLoadGame});

  /// Null hides the load button.
  final VoidCallback? onLoadGame;

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  late final Future<SlotInfo?> _autosave = context
      .read<GameController>()
      .newestAutosave();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final controller = context.read<GameController>();
    final locale = Localizations.localeOf(context);
    return Scaffold(
      appBar: AppBar(actions: const [SettingsButton()]),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l.appTitle,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 32),
                  FutureBuilder(
                    future: _autosave,
                    builder: (context, snap) {
                      final info = snap.data;
                      return FilledButton(
                        onPressed: info == null
                            ? null
                            : () => unawaited(controller.continueLast()),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: Column(
                          children: [
                            Text(l.continueGame),
                            Text(
                              info == null
                                  ? l.noSavedGame
                                  : '${info.clubName ?? info.managerName} · '
                                        '${formatDate(info.date, locale)}',
                              textAlign: TextAlign.center,
                              // Merges with the button's text style, keeping
                              // its foreground colour.
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const NewGameScreen(),
                      ),
                    ),
                    child: Text(l.newGame),
                  ),
                  if (widget.onLoadGame != null) ...[
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: widget.onLoadGame,
                      child: Text(l.loadGame),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
