import 'package:flutter/material.dart';

import '../../engine/snapshots.dart';
import '../../l10n/generated/app_localizations.dart';

/// The in-game scaffold: four tabs behind a bottom navigation bar.
class GameShell extends StatefulWidget {
  const GameShell({super.key, required this.home});

  final HomeSnapshot home;

  @override
  State<GameShell> createState() => _GameShellState();
}

class _GameShellState extends State<GameShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final unread = widget.home.unreadCount;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.home.clubName ?? widget.home.managerName),
      ),
      // Placeholders until the tab screens land.
      body: IndexedStack(
        index: _tab,
        children: const [
          Placeholder(key: Key('homeTab')),
          Placeholder(key: Key('squadTab')),
          Placeholder(key: Key('leagueTab')),
          Placeholder(key: Key('inboxTab')),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            label: l.tabHome,
          ),
          NavigationDestination(
            icon: const Icon(Icons.groups_outlined),
            label: l.tabSquad,
          ),
          NavigationDestination(
            icon: const Icon(Icons.leaderboard_outlined),
            label: l.tabLeague,
          ),
          NavigationDestination(
            icon: unread > 0
                ? Badge(
                    label: Text('$unread'),
                    child: const Icon(Icons.mail_outline),
                  )
                : const Icon(Icons.mail_outline),
            label: l.tabInbox,
          ),
        ],
      ),
    );
  }
}
