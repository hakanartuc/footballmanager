typedef PlayerId = int;
typedef ClubId = int;
typedef LeagueId = int;
typedef CountryId = int;
typedef ManagerId = int;
typedef FixtureId = int;

/// Issues sequential ids per kind (e.g. `'player'`, `'club'`), starting at 1.
class IdAllocator {
  final Map<String, int> _last;

  IdAllocator() : _last = {};

  /// Restores from [toJson] output: the last-issued id per kind.
  IdAllocator.fromJson(Map<String, dynamic> json)
    : _last = {for (final e in json.entries) e.key: e.value as int};

  int next(String kind) => _last[kind] = (_last[kind] ?? 0) + 1;

  Map<String, int> toJson() => Map.of(_last);
}
