import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_version.dart';
import '../../data/settings_controller.dart';
import '../../l10n/formatters.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../state/game_controller.dart';

/// AppBar action that opens [SettingsScreen].
class SettingsButton extends StatelessWidget {
  const SettingsButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
    icon: const Icon(Icons.settings_outlined),
    tooltip: AppLocalizations.of(context)!.settings,
    onPressed: () => Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
  );
}

/// Language, developer stats (with a game) and about.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsController>();
    final controller = context.read<GameController>();
    final state = controller.state;
    return Scaffold(
      appBar: AppBar(title: Text(l.settings)),
      body: ListView(
        children: [
          _Header(l.language),
          // 'system' stands for a null locale.
          RadioGroup<String>(
            groupValue: settings.locale?.languageCode ?? 'system',
            onChanged: (code) => settings.setLocale(
              code == null || code == 'system' ? null : Locale(code),
            ),
            child: Column(
              children: [
                RadioListTile<String>(
                  value: 'system',
                  title: Text(l.systemLanguage),
                ),
                RadioListTile<String>(value: 'tr', title: Text(l.turkish)),
                RadioListTile<String>(value: 'en', title: Text(l.english)),
              ],
            ),
          ),
          if (state case Ready(:final home, :final refs)) ...[
            _Header(l.devStats),
            ListTile(title: Text(l.lastAdvanceMs(controller.lastAdvanceMs))),
            ListTile(title: Text(l.lastSaveMs(controller.lastSaveMs))),
            ListTile(
              title: Text(l.worldSize),
              trailing: Text(
                worldSizeName(sizeFromCountryCount(refs.countries.length), l),
              ),
            ),
            ListTile(
              title: Text(l.season),
              trailing: Text(seasonLabel(home.seasonYear)),
            ),
            ListTile(
              title: Text(l.engineVersion),
              trailing: const Text(engineVersion),
            ),
          ],
          _Header(l.about),
          ListTile(
            title: Text(l.appTitle),
            subtitle: Text(l.version(appVersion)),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}
