import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../engine/engine_gateway.dart';
import '../../engine/snapshots.dart';
import '../../l10n/formatters.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../state/game_controller.dart';
import '../widgets/error_card.dart';

/// One player's profile: header, attribute tabs (a goalkeeping tab first
/// for keepers) and an info tab with contract, season stats and condition.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.playerId});

  final PlayerId playerId;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late Future<PlayerDetail> _detail = _fetch();

  Future<PlayerDetail> _fetch() =>
      context.read<GameController>().player(widget.playerId);

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _detail,
    builder: (context, snap) {
      if (snap.data case final p?) return _PlayerView(p);
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: switch (snap.error) {
            final GatewayError e => ErrorCard(
              error: e,
              onRetry: () => setState(() {
                _detail = _fetch();
              }),
              onDismiss: () => Navigator.of(context).pop(),
            ),
            _ => const CircularProgressIndicator(),
          },
        ),
      );
    },
  );
}

class _PlayerView extends StatelessWidget {
  const _PlayerView(this.p);

  final PlayerDetail p;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final text = Theme.of(context).textTheme;
    final groups = [
      if (p.position == Position.gk) AttrGroup.goalkeeping,
      AttrGroup.technical,
      AttrGroup.mental,
      AttrGroup.physical,
    ];
    final familiar = p.familiarity.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${positionName(p.position, l)} · ${l.age} ${p.age}',
            style: text.titleMedium,
          ),
          Text('${countryName(p.countryCode, l)} · ${l.heightCm(p.heightCm)}'),
          Text('${l.ca} ${p.ca} · ${l.pa} ${p.pa}'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final e in familiar)
                Chip(
                  label: Text('${positionCode(e.key)} ${e.value}'),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
      ),
    );

    return DefaultTabController(
      length: groups.length + 1,
      child: Scaffold(
        appBar: AppBar(
          title: Text(p.name),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              for (final g in groups) Tab(text: attrGroupName(g, l)),
              Tab(text: l.info),
            ],
          ),
        ),
        body: Column(
          children: [
            header,
            Expanded(
              child: TabBarView(
                children: [
                  for (final g in groups) _AttrList(p, g),
                  _InfoList(p),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttrList extends StatelessWidget {
  const _AttrList(this.p, this.group);

  final PlayerDetail p;
  final AttrGroup group;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        for (final a in Attr.values)
          if (attrGroupOf(a) == group)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(child: Text(attrName(a, l))),
                  SizedBox(
                    width: 96,
                    child: LinearProgressIndicator(
                      value: p.attrs[a.index] / 20,
                    ),
                  ),
                  SizedBox(
                    width: 32,
                    child: Text(
                      '${p.attrs[a.index]}',
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

class _InfoList extends StatelessWidget {
  const _InfoList(this.p);

  final PlayerDetail p;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context);
    final text = Theme.of(context).textTheme;
    Widget section(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Text(title, style: text.titleSmall),
    );
    Widget row(String label, String value) =>
        ListTile(dense: true, title: Text(label), trailing: Text(value));

    return ListView(
      children: [
        if (p.wageWeekly case final wage?) ...[
          section(l.contract),
          if (p.status case final status?)
            ListTile(dense: true, title: Text(statusName(status, l))),
          row(l.wage, money(wage, locale)),
          if (p.contractEnd case final end?)
            row(l.contractEnd, formatDate(end, locale)),
        ],
        section(l.seasonStats),
        row(l.apps, '${p.apps}'),
        row(l.goals, '${p.goals}'),
        row(l.assists, '${p.assists}'),
        const Divider(height: 32),
        row(l.condition, '${p.condition.round()}'),
        row(l.morale, '${p.morale.round()}'),
        row(l.form, p.form.toStringAsFixed(1)),
      ],
    );
  }
}
