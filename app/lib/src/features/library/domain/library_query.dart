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
    this.field = SortField.added,
    this.ascending = true,
  });

  final String search;
  final bool favouritesOnly;
  final String? tag;
  final String? developerId;
  final SortField field;
  final bool ascending;
}

List<Game> applyQuery(List<Game> games, LibraryQuery q) {
  final needle = q.search.toLowerCase();
  final tag = q.tag?.toLowerCase();
  final kept = games.where((g) {
    if (needle.isNotEmpty && !g.title.toLowerCase().contains(needle)) {
      return false;
    }
    if (q.favouritesOnly && !g.favourite) return false;
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
    return true;
  }).toList();
  int byTitle(Game a, Game b) =>
      a.title.toLowerCase().compareTo(b.title.toLowerCase());
  final dir = q.ascending ? 1 : -1;
  int compare(Game a, Game b) {
    switch (q.field) {
      case SortField.title:
        return byTitle(a, b) * dir;
      case SortField.lastPlayed:
        // Never-played games sort last in both directions.
        final pa = a.lastPlayedAt;
        final pb = b.lastPlayedAt;
        if (pa == null && pb == null) return byTitle(a, b);
        if (pa == null) return 1;
        if (pb == null) return -1;
        final c = pa.compareTo(pb);
        return c != 0 ? c * dir : byTitle(a, b);
      case SortField.playtime:
        final c =
            a.totalPlaytimeSeconds.compareTo(b.totalPlaytimeSeconds);
        return c != 0 ? c * dir : byTitle(a, b);
      case SortField.vndbRating:
        // Null ratings sort last in both directions.
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

  kept.sort(compare);
  return kept;
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
