import 'package:flutter/material.dart';

import '../../engine/snapshots.dart';
import '../../l10n/generated/app_localizations.dart';
import '../home/home_screen.dart';
import '../squad/lineup_screen.dart';
import '../squad/squad_screen.dart';

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
    final clubId = widget.home.clubId;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.home.clubName ?? widget.home.managerName),
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          HomeScreen(
            key: const Key('homeTab'),
            onOpenInbox: () => setState(() => _tab = 3),
            onOpenLineup: clubId == null
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => LineupScreen(clubId: clubId),
                    ),
                  ),
          ),
          const SquadScreen(key: Key('squadTab')),
          // Placeholders until the other tab screens land.
          const Placeholder(key: Key('leagueTab')),
          const Placeholder(key: Key('inboxTab')),
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
