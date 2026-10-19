// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import '../../../constants/pref_keys.dart';
import '../../../core/model.dart';

/// Prefix that marks a tag filter as a VNDB tag rather than one of the user's.
const String vndbTagPrefix = 'vndb:';

/// The tag-filter value for a VNDB tag name.
String vndbTagFilter(String name) => '$vndbTagPrefix$name';

class LibraryQuery {
  const LibraryQuery({
    this.search = '',
    this.favouritesOnly = false,
    this.tag,
    this.developerId,
    this.adult = AdultFilter.all,
    this.field = SortField.added,
    this.ascending = true,
  });

  final String search;
  final bool favouritesOnly;
  final String? tag;
  final String? developerId;
  final AdultFilter adult;
  final SortField field;
  final bool ascending;
}

List<Game> applyQuery(List<Game> games, LibraryQuery q) {
  final needle = q.search.toLowerCase();
  final kept = games.where((g) => _matches(g, needle, q)).toList();
  kept.sort((a, b) => _compareGames(a, b, q));
  return kept;
}

/// One grid tile: either a single game or a group shown as one tile.
sealed class LibraryTile {
  const LibraryTile();

  String get key;
  String get title;
}

class SingleTile extends LibraryTile {
  const SingleTile(this.game);

  final Game game;

  @override
  String get key => game.id;

  @override
  String get title => game.title;
}

class GroupTile extends LibraryTile {
  const GroupTile({required this.group, required this.members});

  final GameGroup group;
  final List<Game> members;

  /// The first member's cover shows on the group tile.
  Game get coverGame => members.first;

  @override
  String get key => group.id;

  @override
  String get title => group.name;
}

bool _matches(Game g, String needle, LibraryQuery q) {
  if (needle.isNotEmpty && !g.title.toLowerCase().contains(needle)) {
    return false;
  }
  if (q.favouritesOnly && !g.favourite) return false;
  final tag = q.tag?.toLowerCase();
  if (tag != null && tag.startsWith(vndbTagPrefix)) {
    final name = tag.substring(vndbTagPrefix.length);
    if (!g.vndbTags.any(
      (t) => t.rating >= 1.0 && t.name.toLowerCase() == name,
    )) {
      return false;
    }
  } else if (tag != null &&
      tag.isNotEmpty &&
      !g.tags.any((t) => t.toLowerCase() == tag)) {
    return false;
  }
  if (q.developerId != null &&
      !g.developers.any((d) => d.id == q.developerId)) {
    return false;
  }
  if (q.adult == AdultFilter.hide && g.isAdult) return false;
  if (q.adult == AdultFilter.only && !g.isAdult) return false;
  return true;
}

int _compareGames(Game a, Game b, LibraryQuery q) {
  int byTitle(Game x, Game y) =>
      x.title.toLowerCase().compareTo(y.title.toLowerCase());
  final dir = q.ascending ? 1 : -1;
  switch (q.field) {
    case SortField.title:
      return byTitle(a, b) * dir;
    case SortField.lastPlayed:
      final pa = a.lastPlayedAt;
      final pb = b.lastPlayedAt;
      if (pa == null && pb == null) return byTitle(a, b);
      if (pa == null) return 1;
      if (pb == null) return -1;
      final c = pa.compareTo(pb);
      return c != 0 ? c * dir : byTitle(a, b);
    case SortField.playtime:
      final c = a.totalPlaytimeSeconds.compareTo(b.totalPlaytimeSeconds);
      return c != 0 ? c * dir : byTitle(a, b);
    case SortField.vndbRating:
      final ra = a.vndbRating;
      final rb = b.vndbRating;
      if (ra == null && rb == null) return byTitle(a, b);
      if (ra == null) return 1;
      if (rb == null) return -1;
      final c = ra.compareTo(rb);
      return c != 0 ? c * dir : byTitle(a, b);
    case SortField.added:
      final c = a.addedAt.compareTo(b.addedAt);
      return c != 0 ? c * dir : byTitle(a, b);
  }
}

/// The grid tiles for [library]: group members collapse into one tile per
/// group. A group shows when any member passes the filters; search matches
/// the group name or any member's title. A group sorts by the value of
/// whichever member would come first under the current sort (title sort
/// uses the group name).
List<LibraryTile> applyGroupedQuery(Library library, LibraryQuery q) {
  final needle = q.search.toLowerCase();
  final byId = {for (final g in library.games) g.id: g};
  final groupedIds = <String>{};
  final tiles = <LibraryTile>[];
  for (final group in library.groups) {
    final members = [
      for (final id in group.memberIds)
        if (byId[id] != null) byId[id]!,
    ];
    if (members.isEmpty) continue;
    groupedIds.addAll(members.map((g) => g.id));
    final nameHit =
        needle.isNotEmpty && group.name.toLowerCase().contains(needle);
    final passing = [
      for (final m in members)
        if (_matches(m, nameHit ? '' : needle, q)) m,
    ];
    if (passing.isEmpty) continue;
    tiles.add(GroupTile(group: group, members: members));
  }
  for (final game in library.games) {
    if (groupedIds.contains(game.id)) continue;
    if (!_matches(game, needle, q)) continue;
    tiles.add(SingleTile(game));
  }
  Game representative(LibraryTile tile) {
    if (tile is SingleTile) return tile.game;
    final members = (tile as GroupTile).members;
    var best = members.first;
    for (final m in members.skip(1)) {
      if (_compareGames(m, best, q) < 0) best = m;
    }
    return best;
  }

  tiles.sort((a, b) {
    if (q.field == SortField.title) {
      final c = a.title.toLowerCase().compareTo(b.title.toLowerCase());
      return q.ascending ? c : -c;
    }
    final c = _compareGames(representative(a), representative(b), q);
    if (c != 0) return c;
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  });
  return tiles;
}

List<String> allTags(List<Game> games) {
  final seen = <String, String>{};
  for (final game in games) {
    for (final tag in game.tags) {
      seen.putIfAbsent(tag.toLowerCase(), () => tag);
    }
  }
  final tags = seen.values.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return tags;
}

/// VNDB tag names on at least one game at rating 2.0 or more and spoiler 0,
/// with the number of games carrying each, most common first.
List<(String, int)> vndbTagCounts(List<Game> games) {
  final counts = <String, int>{};
  final names = <String, String>{};
  for (final game in games) {
    final seen = <String>{};
    for (final tag in game.vndbTags) {
      if (tag.spoiler != 0 || tag.rating < 2.0) continue;
      final key = tag.name.toLowerCase();
      if (!seen.add(key)) continue;
      counts.update(key, (n) => n + 1, ifAbsent: () => 1);
      names.putIfAbsent(key, () => tag.name);
    }
  }
  final result = [for (final e in counts.entries) (names[e.key]!, e.value)];
  result.sort((a, b) {
    final byCount = b.$2.compareTo(a.$2);
    if (byCount != 0) return byCount;
    return a.$1.toLowerCase().compareTo(b.$1.toLowerCase());
  });
  return result;
}
