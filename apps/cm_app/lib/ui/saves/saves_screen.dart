import 'dart:async';

import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/game_repository.dart';
import '../../engine/engine_gateway.dart';
import '../../l10n/formatters.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../state/game_controller.dart';
import '../widgets/error_card.dart';

/// The manual save slots and the autosaves. Every slot can be loaded or
/// deleted; with [canSave] (a game is loaded) manual slots can be saved to.
class SavesScreen extends StatefulWidget {
  const SavesScreen({super.key, required this.canSave});

  final bool canSave;

  @override
  State<SavesScreen> createState() => _SavesScreenState();
}

typedef _Slots = (List<SlotInfo> manual, List<SlotInfo> autosaves);

class _SavesScreenState extends State<SavesScreen> {
  late Future<_Slots> _slots = _read();

  /// Inline error text per slot, from its last failed action.
  final Map<int, String> _errors = {};

  GameController get _controller => context.read<GameController>();

  Future<_Slots> _read() async =>
      (await _controller.manualSlots(), await _controller.autosaves());

  void _refresh() {
    setState(() {
      _slots = _read();
    });
  }

  Future<bool> _confirm(String question) async {
    final l = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(question),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.ok),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  /// Shows a [Failed] action's error on [slot]'s row and dismisses it so
  /// the root error barrier does not appear; true when it failed.
  bool _failedOn(int slot, String Function(GatewayError e) text) {
    final state = _controller.state;
    if (state is! Failed) return false;
    setState(() => _errors[slot] = text(state.error));
    _controller.dismissError();
    return true;
  }

  Future<void> _save(int slot, {required bool occupied}) async {
    final l = AppLocalizations.of(context)!;
    if (occupied && !await _confirm(l.overwriteConfirm)) return;
    setState(() => _errors.remove(slot));
    await _controller.saveToSlot(slot);
    if (!mounted || _failedOn(slot, (_) => l.error)) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l.saved)));
    _refresh();
  }

  Future<void> _load(int slot) async {
    final l = AppLocalizations.of(context)!;
    setState(() => _errors.remove(slot));
    await _controller.loadSlot(slot);
    if (!mounted) return;
    final failed = _failedOn(
      slot,
      (e) => e.saveKind == SaveErrorKind.newerSchema
          ? l.newerSaveError
          : l.loadError,
    );
    if (!failed) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _delete(int slot) async {
    final l = AppLocalizations.of(context)!;
    if (!await _confirm(l.deleteConfirm)) return;
    setState(() => _errors.remove(slot));
    try {
      await _controller.deleteSlot(slot);
    } on SaveError {
      if (mounted) setState(() => _errors[slot] = l.error);
      return;
    }
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    // Actions throw while one runs, so their buttons are disabled.
    final busy = context.watch<GameController>().state is Busy;
    return Scaffold(
      appBar: AppBar(title: Text(l.manualSaves)),
      body: FutureBuilder(
        future: _slots,
        builder: (context, snap) {
          final data = snap.data;
          if (snap.connectionState == ConnectionState.done && snap.hasError) {
            return ErrorCard(
              error: GatewayError(GatewayErrorKind.save, '${snap.error}'),
              onRetry: _refresh,
            );
          }
          if (data == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final (manual, autosaves) = data;
          final bySlot = {for (final s in manual) s.slot: s};
          VoidCallback? run(Future<void> Function() action) =>
              busy ? null : () => unawaited(action());
          return ListView(
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              for (final n in manualSlots)
                _SlotCard(
                  key: Key('slot$n'),
                  title: l.slot(n),
                  info: bySlot[n],
                  error: _errors[n],
                  actions: [
                    if (widget.canSave)
                      TextButton(
                        onPressed: run(
                          () => _save(n, occupied: bySlot.containsKey(n)),
                        ),
                        child: Text(l.save),
                      ),
                    if (bySlot.containsKey(n)) ...[
                      TextButton(
                        onPressed: run(() => _load(n)),
                        child: Text(l.load),
                      ),
                      TextButton(
                        onPressed: run(() => _delete(n)),
                        child: Text(l.delete),
                      ),
                    ],
                  ],
                ),
              if (autosaves.isNotEmpty) _Header(l.autosaves),
              for (final s in autosaves)
                _SlotCard(
                  key: Key('autosave${s.slot}'),
                  info: s,
                  error: _errors[s.slot],
                  actions: [
                    TextButton(
                      onPressed: run(() => _load(s.slot)),
                      child: Text(l.load),
                    ),
                  ],
                ),
            ],
          );
        },
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
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}

/// One slot: an optional [title], what [info] holds (or empty), [error]
/// and [actions].
class _SlotCard extends StatelessWidget {
  const _SlotCard({
    super.key,
    this.title,
    required this.info,
    required this.error,
    required this.actions,
  });

  final String? title;
  final SlotInfo? info;
  final String? error;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context);
    final info = this.info;
    final muted = TextStyle(color: theme.colorScheme.onSurfaceVariant);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title case final title?)
              Text(title, style: theme.textTheme.titleMedium),
            if (info == null)
              Text(l.emptySlot, style: muted)
            else ...[
              Text(
                '${info.clubName ?? info.managerName} · '
                '${formatDate(info.date, locale)} · '
                '${seasonLabel(info.seasonYear)}',
              ),
              Text(
                DateFormat.yMd(
                  locale.toLanguageTag(),
                ).add_Hm().format(info.savedAt.toLocal()),
                style: theme.textTheme.bodySmall?.merge(muted),
              ),
            ],
            if (error case final error?)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  error,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              spacing: 8,
              children: actions,
            ),
          ],
        ),
      ),
    );
  }
}
