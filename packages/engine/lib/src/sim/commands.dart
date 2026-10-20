import '../core/ids.dart';
import '../model/club.dart';

/// A user action applied to the world.
sealed class Command {
  const Command();
}

/// Sets [clubId]'s lineup.
final class SetLineup extends Command {
  final ClubId clubId;
  final Lineup lineup;

  const SetLineup({required this.clubId, required this.lineup});
}

/// Clears [clubId]'s lineup so the next match picks one automatically.
final class ClearLineup extends Command {
  final ClubId clubId;

  const ClearLineup({required this.clubId});
}
