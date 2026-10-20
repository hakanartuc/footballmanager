enum Position { gk, dl, dc, dr, dm, ml, mc, mr, aml, amc, amr, st }

enum PositionGroup { gk, def, mid, att }

extension PositionX on Position {
  PositionGroup get group => switch (this) {
    Position.gk => PositionGroup.gk,
    Position.dl || Position.dc || Position.dr => PositionGroup.def,
    Position.dm ||
    Position.ml ||
    Position.mc ||
    Position.mr => PositionGroup.mid,
    Position.aml ||
    Position.amc ||
    Position.amr ||
    Position.st => PositionGroup.att,
  };
}

enum Attr {
  // technical
  passing,
  longShots,
  firstTouch,
  dribbling,
  crossing,
  heading,
  longPassing,
  finishing,
  tackling,
  // mental
  decisions,
  positioning,
  anticipation,
  composure,
  workRate,
  teamwork,
  aggression,
  concentration,
  leadership,
  // physical
  pace,
  acceleration,
  stamina,
  strength,
  balance,
  jumping,
  agility,
  // goalkeeping
  reflexes,
  aerialAbility,
  handling,
  oneOnOnes,
  commandOfArea,
}

enum Formation { f442, f433, f451, f352, f4231, f532 }

/// The 11 positions of [f]; index 0 is always the goalkeeper.
List<Position> formationSlots(Formation f) => switch (f) {
  Formation.f442 => const [
    Position.gk,
    Position.dl,
    Position.dc,
    Position.dc,
    Position.dr,
    Position.ml,
    Position.mc,
    Position.mc,
    Position.mr,
    Position.st,
    Position.st,
  ],
  Formation.f433 => const [
    Position.gk,
    Position.dl,
    Position.dc,
    Position.dc,
    Position.dr,
    Position.mc,
    Position.mc,
    Position.mc,
    Position.aml,
    Position.amr,
    Position.st,
  ],
  Formation.f451 => const [
    Position.gk,
    Position.dl,
    Position.dc,
    Position.dc,
    Position.dr,
    Position.ml,
    Position.mc,
    Position.mc,
    Position.mc,
    Position.mr,
    Position.st,
  ],
  Formation.f352 => const [
    Position.gk,
    Position.dc,
    Position.dc,
    Position.dc,
    Position.ml,
    Position.mc,
    Position.mc,
    Position.mc,
    Position.mr,
    Position.st,
    Position.st,
  ],
  Formation.f4231 => const [
    Position.gk,
    Position.dl,
    Position.dc,
    Position.dc,
    Position.dr,
    Position.dm,
    Position.dm,
    Position.aml,
    Position.amc,
    Position.amr,
    Position.st,
  ],
  Formation.f532 => const [
    Position.gk,
    Position.dl,
    Position.dc,
    Position.dc,
    Position.dc,
    Position.dr,
    Position.mc,
    Position.mc,
    Position.mc,
    Position.st,
    Position.st,
  ],
};

enum PlayerStatus { keyPlayer, firstTeam, rotation, backup, hotProspect, youth }

enum BoardExpectation { title, top, upperMid, mid, avoidRelegation }

enum Continent { europe, southAmerica, northAmerica, africa, asia, oceania }
