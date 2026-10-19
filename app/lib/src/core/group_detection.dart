// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'groups.dart';
import 'model.dart';

/// An episode group the library can offer for the user to confirm.
class GroupSuggestion {
  final String name;
  final List<String> memberIds;
  final String reason;

  const GroupSuggestion({
    required this.name,
    required this.memberIds,
    required this.reason,
  });

  /// Stable identity for dismissals: member ids sorted lexicographically.
  String get key => ([...memberIds]..sort()).join(',');
}

/// Matches a numbered part marker: `Episode N`, `Ep. N`, `Chapter N`,
/// `Ch. N`, `Volume N`, `Vol. N`, `Part N`, `第N話` / `第N章`. Each marker
/// word starts at a word boundary; a bare number does not count.
final RegExp _partPattern = RegExp(
  r'\b(?:episode|chapter|volume|part|ep|ch|vol)\b\.?\s*'
  r'([0-9０-９]+(?:[.．][0-9０-９]+)?)'
  r'|第\s*([0-9０-９]+(?:[.．][0-9０-９]+)?)\s*[話章]',
  caseSensitive: false,
);

class _Part {
  final String prefix;
  final String normalized;

  const _Part(this.prefix, this.normalized);
}

/// The part marker in [title], or null when the title names no numbered part.
_Part? _partOf(String title) {
  final match = _partPattern.firstMatch(title);
  if (match == null) return null;
  final prefix = _cleanPrefix(title.substring(0, match.start));
  return _Part(
    prefix,
    prefix.toLowerCase().replaceAll(RegExp(r'\s+'), ' '),
  );
}

/// Trims whitespace and any trailing separators such as ` -`, ` :`, ` –`.
/// A hyphen glued to a word (`9-nine-`) is part of the name and stays.
String _cleanPrefix(String raw) {
  var prefix = raw;
  final trailing = RegExp(r'\s+[-:–]\s*$');
  while (true) {
    final next = prefix.replaceFirst(trailing, '');
    if (next == prefix) break;
    prefix = next;
  }
  return prefix.trim();
}

bool _sharesVndb(Game a, Game b) =>
    a.vndbId != null && a.vndbId == b.vndbId;

bool _sequelLinked(Game a, Game b) =>
    _hasSequelRelation(a, b.vndbId) || _hasSequelRelation(b, a.vndbId);

bool _hasSequelRelation(Game game, String? otherVndbId) {
  if (otherVndbId == null) return false;
  return game.relations.any((r) =>
      r.official &&
      (r.relation == 'seq' || r.relation == 'preq') &&
      r.vndbId == otherVndbId);
}

/// Suggests episode groups the user can confirm.
///
/// Two games join a suggestion when they are linked (same VNDB id, or an
/// official `seq`/`preq` relation between them), both titles carry a part
/// marker with a number, and the text before the marker matches. Members of
/// existing groups and suggestions whose [GroupSuggestion.key] is in
/// [dismissed] are left out.
List<GroupSuggestion> suggestGroups(
  Library library, {
  Set<String> dismissed = const {},
}) {
  final games = library.games;
  final parts = [for (final g in games) _partOf(g.title)];

  final byPrefix = <String, List<int>>{};
  for (var i = 0; i < games.length; i++) {
    final part = parts[i];
    if (part == null) continue;
    byPrefix.putIfAbsent(part.normalized, () => []).add(i);
  }

  final parent = List<int>.generate(games.length, (i) => i);
  int find(int i) {
    while (parent[i] != i) {
      parent[i] = parent[parent[i]];
      i = parent[i];
    }
    return i;
  }

  void union(int a, int b) {
    final ra = find(a);
    final rb = find(b);
    if (ra != rb) parent[rb] = ra;
  }

  final classes = <int, bool>{};
  final sequels = <int, bool>{};
  final edges = <(int, int, bool, bool)>[];
  for (final indices in byPrefix.values) {
    for (var a = 0; a < indices.length; a++) {
      for (var b = a + 1; b < indices.length; b++) {
        final i = indices[a];
        final j = indices[b];
        final shared = _sharesVndb(games[i], games[j]);
        final sequel = _sequelLinked(games[i], games[j]);
        if (!shared && !sequel) continue;
        union(i, j);
        edges.add((i, j, shared, sequel));
      }
    }
  }
  for (final (i, _, shared, sequel) in edges) {
    final root = find(i);
    if (shared) classes[root] = true;
    if (sequel) sequels[root] = true;
  }

  final grouped = <String>{
    for (final group in library.groups) ...group.memberIds,
  };
  final partByGameId = <String, _Part>{
    for (var i = 0; i < games.length; i++)
      if (parts[i] != null) games[i].id: parts[i]!,
  };

  final components = <int, List<int>>{};
  for (var i = 0; i < games.length; i++) {
    if (parts[i] == null) continue;
    components.putIfAbsent(find(i), () => []).add(i);
  }

  final suggestions = <GroupSuggestion>[];
  for (final entry in components.entries) {
    if (entry.value.length < 2) continue;
    final members = [
      for (final i in entry.value)
        if (!grouped.contains(games[i].id)) games[i],
    ];
    if (members.length < 2) continue;
    final memberIds = sortEpisodeIds(members);
    final key = ([...memberIds]..sort()).join(',');
    if (dismissed.contains(key)) continue;
    final shared = classes[entry.key] ?? false;
    final sequel = sequels[entry.key] ?? false;
    suggestions.add(GroupSuggestion(
      name: partByGameId[memberIds.first]!.prefix,
      memberIds: memberIds,
      reason: shared && sequel
          ? 'both'
          : shared
              ? 'sharedVndb'
              : 'sequelChain',
    ));
  }

  suggestions.sort((a, b) {
    final byName = a.name.compareTo(b.name);
    return byName != 0 ? byName : a.key.compareTo(b.key);
  });
  return suggestions;
}
