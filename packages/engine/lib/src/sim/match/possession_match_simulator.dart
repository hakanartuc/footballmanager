import '../../model/match_result.dart';
import '../match_simulator.dart';
import 'match_session.dart';

/// The possession match engine (spec 5.3) as a [MatchSimulator]: a
/// [MatchSession] run to the end without interruption. The day loop's
/// default stays `PoissonMatchSimulator` until the swap.
class PossessionMatchSimulator implements MatchSimulator {
  const PossessionMatchSimulator();

  @override
  MatchResult simulate(MatchContext ctx) => MatchSession(ctx).finish();
}
