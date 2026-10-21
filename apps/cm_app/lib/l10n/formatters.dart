import 'package:engine/engine.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import 'generated/app_localizations.dart';

/// Short date, e.g. "8 Ağu 2026" / "Aug 8, 2026".
///
/// Needs the locale's date symbols; the app's `flutter_localizations`
/// delegates load them at runtime, plain tests call
/// `initializeDateFormatting`.
String formatDate(GameDate d, Locale locale) => DateFormat.yMMMd(
  locale.toLanguageTag(),
).format(DateTime.utc(d.year, d.month, d.day));

/// "2026-27" for the season starting in 2026.
String seasonLabel(int year) =>
    '$year-${((year + 1) % 100).toString().padLeft(2, '0')}';

/// Locale-independent short code: "GK", "DL", … "ST".
String positionCode(Position p) => p.name.toUpperCase();

String positionName(Position p, AppLocalizations l) => switch (p) {
  Position.gk => l.posGk,
  Position.dl => l.posDl,
  Position.dc => l.posDc,
  Position.dr => l.posDr,
  Position.dm => l.posDm,
  Position.ml => l.posMl,
  Position.mc => l.posMc,
  Position.mr => l.posMr,
  Position.aml => l.posAml,
  Position.amc => l.posAmc,
  Position.amr => l.posAmr,
  Position.st => l.posSt,
};

/// "4-4-2", "4-2-3-1", …
String formationLabel(Formation f) => f.name.substring(1).split('').join('-');

/// Abstract money unit with thousands separators and no symbol.
String money(int v, Locale locale) =>
    NumberFormat.decimalPattern(locale.toLanguageTag()).format(v);

String attrName(Attr a, AppLocalizations l) => switch (a) {
  Attr.passing => l.attrPassing,
  Attr.longShots => l.attrLongShots,
  Attr.firstTouch => l.attrFirstTouch,
  Attr.dribbling => l.attrDribbling,
  Attr.crossing => l.attrCrossing,
  Attr.heading => l.attrHeading,
  Attr.longPassing => l.attrLongPassing,
  Attr.finishing => l.attrFinishing,
  Attr.tackling => l.attrTackling,
  Attr.decisions => l.attrDecisions,
  Attr.positioning => l.attrPositioning,
  Attr.anticipation => l.attrAnticipation,
  Attr.composure => l.attrComposure,
  Attr.workRate => l.attrWorkRate,
  Attr.teamwork => l.attrTeamwork,
  Attr.aggression => l.attrAggression,
  Attr.concentration => l.attrConcentration,
  Attr.leadership => l.attrLeadership,
  Attr.pace => l.attrPace,
  Attr.acceleration => l.attrAcceleration,
  Attr.stamina => l.attrStamina,
  Attr.strength => l.attrStrength,
  Attr.balance => l.attrBalance,
  Attr.jumping => l.attrJumping,
  Attr.agility => l.attrAgility,
  Attr.reflexes => l.attrReflexes,
  Attr.aerialAbility => l.attrAerialAbility,
  Attr.handling => l.attrHandling,
  Attr.oneOnOnes => l.attrOneOnOnes,
  Attr.commandOfArea => l.attrCommandOfArea,
};

enum AttrGroup { technical, mental, physical, goalkeeping }

/// First [Attr] index of each group; [Attr] declares its groups in this
/// order: technical 0–8, mental 9–17, physical 18–24, goalkeeping 25–29.
const _attrGroupStart = {
  AttrGroup.technical: 0,
  AttrGroup.mental: 9,
  AttrGroup.physical: 18,
  AttrGroup.goalkeeping: 25,
};

AttrGroup attrGroupOf(Attr a) =>
    AttrGroup.values.lastWhere((g) => a.index >= _attrGroupStart[g]!);

String attrGroupName(AttrGroup g, AppLocalizations l) => switch (g) {
  AttrGroup.technical => l.attrGroupTechnical,
  AttrGroup.mental => l.attrGroupMental,
  AttrGroup.physical => l.attrGroupPhysical,
  AttrGroup.goalkeeping => l.attrGroupGoalkeeping,
};

String statusName(PlayerStatus s, AppLocalizations l) => switch (s) {
  PlayerStatus.keyPlayer => l.statusKeyPlayer,
  PlayerStatus.firstTeam => l.statusFirstTeam,
  PlayerStatus.rotation => l.statusRotation,
  PlayerStatus.backup => l.statusBackup,
  PlayerStatus.hotProspect => l.statusHotProspect,
  PlayerStatus.youth => l.statusYouth,
};

String lineupErrorText(LineupError e, AppLocalizations l) => switch (e) {
  LineupError.notEleven => l.lineupErrorNotEleven,
  LineupError.duplicate => l.lineupErrorDuplicate,
  LineupError.notInClub => l.lineupErrorNotInClub,
  LineupError.noGoalkeeper => l.lineupErrorNoGoalkeeper,
  LineupError.ineligible => l.lineupErrorIneligible,
};

/// Localized name of a country [code]; an unknown code is returned as is.
String countryName(String code, AppLocalizations l) => switch (code) {
  'TR' => l.countryTR,
  'ENG' => l.countryENG,
  'ES' => l.countryES,
  'DE' => l.countryDE,
  'IT' => l.countryIT,
  'FR' => l.countryFR,
  'NL' => l.countryNL,
  'PT' => l.countryPT,
  'BR' => l.countryBR,
  'AR' => l.countryAR,
  'US' => l.countryUS,
  'MX' => l.countryMX,
  'JP' => l.countryJP,
  'KR' => l.countryKR,
  'NG' => l.countryNG,
  'AU' => l.countryAU,
  _ => code,
};

/// "Türkiye 1. Lig" / "Türkiye Division 1"; never the raw engine name.
String leagueDisplayName(String countryCode, int tier, AppLocalizations l) =>
    l.leagueDisplayName(countryName(countryCode, l), tier);

String worldSizeName(WorldSize s, AppLocalizations l) => switch (s) {
  WorldSize.small => l.worldSizeSmall,
  WorldSize.medium => l.worldSizeMedium,
  WorldSize.large => l.worldSizeLarge,
};

/// The [WorldSize] a world of [count] countries was generated at: the
/// largest size not above [count], else [WorldSize.small].
WorldSize sizeFromCountryCount(int count) => WorldSize.values.lastWhere(
  (s) => s.countryCount <= count,
  orElse: () => WorldSize.small,
);
