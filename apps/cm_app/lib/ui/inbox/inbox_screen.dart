import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../engine/snapshots.dart';
import '../../l10n/event_text.dart';
import '../../l10n/formatters.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../state/game_controller.dart';
import '../widgets/empty_state.dart';
import '../widgets/loaded.dart';
import 'inbox_detail_screen.dart';

/// The inbox tab: messages newest first, unread ones bold with a dot;
/// tapping one marks it read and opens it.
class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  /// The latest [Ready], shown while the controller is [Busy] or [Failed].
  Ready? _ready;

  /// The inbox, refetched whenever home changes (including after
  /// [GameController.markRead], which refreshes home).
  Future<List<InboxItem>>? _items;

  Future<void> _open(GameController controller, InboxItem item) async {
    if (!item.read) {
      await controller.markRead(item.id);
      if (!mounted || controller.state is Failed) return;
    }
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => InboxDetailScreen(item)));
  }

  /// Stops at a failure, and when a busy action started meanwhile.
  Future<void> _markAllRead(
    GameController controller,
    List<InboxItem> items,
  ) async {
    for (final item in items) {
      if (item.read) continue;
      try {
        await controller.markRead(item.id);
      } on StateError catch (e) {
        if (e.message != 'busy') rethrow;
        return;
      }
      if (controller.state is Failed) return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<GameController>();
    final ready = switch (controller.state) {
      final Ready r => r,
      Failed(previous: final Ready r) => r,
      _ => _ready!,
    };
    if (!identical(ready.home, _ready?.home)) _items = null;
    _ready = ready;
    _items ??= controller.inbox();
    final l = AppLocalizations.of(context)!;

    return Loaded(
      future: _items!,
      onRetry: () => setState(() => _items = null),
      empty: EmptyState(text: l.noMessages),
      builder: (items) => [
        if (items.isNotEmpty)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: TextButton(
                onPressed: items.any((i) => !i.read)
                    ? () => _markAllRead(controller, items)
                    : null,
                child: Text(l.markAllRead),
              ),
            ),
          ),
        for (final item in items)
          _InboxTile(item, onTap: () => _open(controller, item)),
      ],
    );
  }
}

class _InboxTile extends StatelessWidget {
  const _InboxTile(this.item, {required this.onTap});

  final InboxItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final text = EventText.describe(item, l);
    return ListTile(
      leading: SizedBox(
        width: 10,
        child: item.read
            ? null
            : DecoratedBox(
                key: const Key('unreadDot'),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(context).colorScheme.primary,
                ),
                child: const SizedBox.square(dimension: 10),
              ),
      ),
      title: Text(
        text.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: item.read ? null : const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Text(text.body, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Text(formatDate(item.date, Localizations.localeOf(context))),
      onTap: onTap,
    );
  }
}
