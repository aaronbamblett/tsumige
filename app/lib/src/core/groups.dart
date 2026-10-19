// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'model.dart';

/// Matches a part number in an episode title: `Episode N`, `Ep. N`,
/// `Chapter N` / `Ch. N`, `Volume N` / `Vol. N`, `Part N`, `第N話` / `第N章`.
/// Decimals such as `Vol.5.5` are allowed.
final RegExp _partPattern = RegExp(
  r'(?:episode|ep\.?|chapter|ch\.?|volume|vol\.?|part)\s*\.?\s*(\d+(?:\.\d+)?)|第\s*(\d+(?:\.\d+)?)\s*[話章]',
  caseSensitive: false,
);

/// The part number in [title], or null when it names no numbered part.
double? episodePartNumber(String title) {
  final match = _partPattern.firstMatch(title);
  if (match == null) return null;
  final raw = match.group(1) ?? match.group(2);
  if (raw == null) return null;
  return double.tryParse(raw);
}

/// Orders member ids once, when a group is created: by the part number in
/// each title, then by release date, then by title. Members without a part
/// number sort after numbered ones. Pure, so suggestions (part 3) can reuse
/// it.
List<String> sortEpisodeIds(List<Game> members) {
  final sorted = members.toList();
  sorted.sort((a, b) {
    final pa = episodePartNumber(a.title);
    final pb = episodePartNumber(b.title);
    if (pa != null && pb != null && pa != pb) return pa.compareTo(pb);
    if (pa == null && pb != null) return 1;
    if (pa != null && pb == null) return -1;
    final ra = a.released ?? '';
    final rb = b.released ?? '';
    if (ra != rb) return ra.compareTo(rb);
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  });
  return [for (final m in sorted) m.id];
}

/// Creates a group with its members in episode order.
GameGroup createGroup({
  required String id,
  required String name,
  required List<Game> members,
  String? lastPickedId,
}) {
  final group = GameGroup(
    id: id,
    name: name,
    memberIds: sortEpisodeIds(members),
  );
  if (lastPickedId != null && group.memberIds.contains(lastPickedId)) {
    group.lastPickedId = lastPickedId;
  }
  return group;
}

/// The member shown when a group opens: the remembered member, else the
/// first member with no play sessions, else the first member.
Game? resolvePickedMember(GameGroup group, Map<String, Game> byId) {
  final last = group.lastPickedId;
  if (last != null && group.memberIds.contains(last)) {
    final game = byId[last];
    if (game != null) return game;
  }
  for (final id in group.memberIds) {
    final game = byId[id];
    if (game != null && game.playSessions.isEmpty) return game;
  }
  for (final id in group.memberIds) {
    final game = byId[id];
    if (game != null) return game;
  }
  return null;
}

/// The member's short name in the episode picker: its title with the group's
/// shared title prefix removed and trimmed; the full title when nothing is
/// left.
String memberShortName(GameGroup group, Game member, Map<String, Game> byId) {
  final titles = [
    for (final id in group.memberIds)
      if (byId[id] != null) byId[id]!.title,
  ];
  var prefix = titles.isEmpty ? '' : titles.first;
  for (final title in titles) {
    var i = 0;
    while (i < prefix.length &&
        i < title.length &&
        prefix[i] == title[i]) {
      i++;
    }
    prefix = prefix.substring(0, i);
  }
  final short = member.title.substring(prefix.length).trim();
  return short.isEmpty ? member.title : short;
}

/// Enforces the group invariants in place; called by every writer (store
/// load/save and the game editor):
/// - a game is in at most one group (first group wins);
/// - a group keeps only existing members, and fewer than 2 dissolves it;
/// - [lastPickedId] must be a member, else null.
void normalizeGroups(Library library) {
  final byId = {for (final g in library.games) g.id: g};
  final claimed = <String>{};
  final kept = <GameGroup>[];
  for (final group in library.groups) {
    final members = <String>[];
    for (final id in group.memberIds) {
      if (!byId.containsKey(id)) continue;
      if (!claimed.add(id)) continue;
      members.add(id);
    }
    if (members.length < 2) continue;
    group.memberIds = members;
    if (!members.contains(group.lastPickedId)) {
      group.lastPickedId = null;
    }
    kept.add(group);
  }
  library.groups
    ..clear()
    ..addAll(kept);
}
