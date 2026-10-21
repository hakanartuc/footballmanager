import 'package:flutter/material.dart';

/// [child] under a scrim and spinner that absorb input while [busy].
class BusyOverlay extends StatelessWidget {
  const BusyOverlay({super.key, required this.busy, required this.child});

  final bool busy;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (busy)
          const Positioned.fill(
            child: AbsorbPointer(
              child: ColoredBox(
                color: Colors.black38,
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
          ),
      ],
    );
  }
}
