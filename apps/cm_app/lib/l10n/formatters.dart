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

String worldSizeName(WorldSize s, AppLocalizations l) => switch (s) {
  WorldSize.small => l.worldSizeSmall,
  WorldSize.medium => l.worldSizeMedium,
  WorldSize.large => l.worldSizeLarge,
};
