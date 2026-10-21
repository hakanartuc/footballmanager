import 'package:engine/engine.dart';

import '../engine/snapshots.dart';
import 'formatters.dart';
import 'generated/app_localizations.dart';

final class EventTextResult {
  const EventTextResult(this.title, this.body);

  final String title;
  final String body;
}

/// Turns an inbox item into a localized headline and one-line body.
abstract final class EventText {
  static EventTextResult describe(InboxItem item, AppLocalizations l) {
    final x = item.labels;
    final club = x.clubName ?? '';
    final league = leagueDisplayName(
      x.leagueCountryCode ?? '',
      x.leagueTier ?? 0,
      l,
    );
    final toLeague = leagueDisplayName(
      x.toLeagueCountryCode ?? '',
      x.toLeagueTier ?? 0,
      l,
    );
    return switch (item.event) {
      MatchPlayed() => EventTextResult(
        l.eventMatchTitle(
          x.homeName ?? '',
          x.homeGoals ?? 0,
          x.awayGoals ?? 0,
          x.awayName ?? '',
        ),
        l.eventMatchBody,
      ),
      LeagueChampion() => EventTextResult(
        l.eventChampionTitle(club, league),
        l.eventChampionBody(club, league),
      ),
      Promoted() => EventTextResult(
        l.eventPromotedTitle(club),
        l.eventPromotedBody(club, league, toLeague),
      ),
      Relegated() => EventTextResult(
        l.eventRelegatedTitle(club),
        l.eventRelegatedBody(club, league, toLeague),
      ),
      PlayerRetired() => EventTextResult(
        x.playerNames.isEmpty
            ? l.eventRetiredTitleUnnamed
            : l.eventRetiredTitle(x.playerNames.first),
        x.clubName == null
            ? l.eventRetiredBodyFree
            : l.eventRetiredBodyClub(club),
      ),
      YouthIntake(:final playerIds) => EventTextResult(
        l.eventYouthIntakeTitle(playerIds.length),
        x.playerNames.isEmpty
            ? l.eventYouthIntakeBodyUnnamed(club)
            : l.eventYouthIntakeBody(club, x.playerNames.join(', ')),
      ),
      YouthReleased(:final playerIds) => EventTextResult(
        l.eventYouthReleasedTitle(playerIds.length),
        l.eventYouthReleasedBody(club),
      ),
      SeasonEnded(:final seasonYear) => EventTextResult(
        l.eventSeasonEndedTitle(seasonLabel(seasonYear)),
        l.eventSeasonEndedBody,
      ),
      NewSeasonStarted(:final seasonYear) => EventTextResult(
        l.eventNewSeasonTitle(seasonLabel(seasonYear)),
        l.eventNewSeasonBody,
      ),
    };
  }
}
