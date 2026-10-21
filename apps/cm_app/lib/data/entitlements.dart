import 'package:engine/engine.dart';

/// What the user may play.
class Entitlements {
  const Entitlements({required this.allowedSizes});

  static const dev = Entitlements(
    allowedSizes: {WorldSize.small, WorldSize.medium, WorldSize.large},
  );

  /// Must be non-empty.
  final Set<WorldSize> allowedSizes;

  bool allows(WorldSize s) => allowedSizes.contains(s);

  /// The largest allowed size, the new-game screen's default. Needs a
  /// non-empty [allowedSizes].
  WorldSize get maxWorldSize =>
      allowedSizes.reduce((a, b) => a.countryCount >= b.countryCount ? a : b);
}
