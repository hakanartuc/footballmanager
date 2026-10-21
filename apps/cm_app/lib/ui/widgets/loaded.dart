import 'package:flutter/material.dart';

import '../../engine/engine_gateway.dart';
import 'error_card.dart';

/// A list of [builder]'s widgets once [future] completes, after an
/// optional [header]; a spinner while loading, an [ErrorCard] on failure
/// and [empty] when it completed with no rows.
class Loaded<T> extends StatelessWidget {
  const Loaded({
    super.key,
    required this.future,
    required this.onRetry,
    required this.builder,
    this.header,
    this.empty,
  });

  final Future<List<T>> future;
  final VoidCallback onRetry;
  final List<Widget> Function(List<T> rows) builder;
  final Widget? header;
  final Widget? empty;

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: future,
    builder: (context, snap) => ListView(
      children: [
        ?header,
        if (snap.error case final GatewayError e)
          ErrorCard(error: e, onRetry: onRetry)
        else if (snap.connectionState != ConnectionState.done)
          const Center(child: CircularProgressIndicator())
        else if (snap.data!.isEmpty)
          ?empty,
        ...builder(snap.data ?? const []),
      ],
    ),
  );
}
