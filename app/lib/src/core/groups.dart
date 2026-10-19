// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'model.dart';

/// Matches a part number in an episode title: `Episode N`, `Ep. N`,
/// `Chapter N` / `Ch. N`, `Volume N` / `Vol. N`, `Part N`, `第N話` / `第N章`.
/// Decimals such as `Vol.5.5` are allowed. The leading word boundary keeps
/// markers inside words (`Sleep 3`) from matching. The `第` branch also
/// accepts fullwidth digits, normalised to ASCII before parsing.
final RegExp _partPattern = RegExp(
  r'(?:\b(?:episode|ep\.?|chapter|ch\.?|volume|vol\.?|part)\s*\.?\s*(\d+(?:\.\d+)?)|第\s*([0-9０-９]+(?:\.[0-9０-９]+)?)\s*[話章])',
  caseSensitive: false,
);

/// Fullwidth digits to their ASCII value.
String _asciiDigits(String raw) => raw.replaceAllMapped(
      RegExp('[０-９]'),
      (m) => String.fromCharCode(m[0]!.codeUnitAt(0) - 0xFF10 + 0x30),
    );

/// The part number in [title], or null when it names no numbered part.
double? episodePartNumber(String title) {
  final match = _partPattern.firstMatch(title);
  if (match == null) return null;
  final raw = match.group(1) ?? match.group(2);
  if (raw == null) return null;
  return double.tryParse(_asciiDigits(raw));
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
    final ra = a.released;
    final rb = b.released;
    if (ra != null && ra.isNotEmpty && rb != null && rb.isNotEmpty) {
      if (ra != rb) return ra.compareTo(rb);
    } else if (ra != null && ra.isNotEmpty) {
      return -1;
    } else if (rb != null && rb.isNotEmpty) {
      return 1;
    }
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

/// Whitespace or punctuation: a title-prefix boundary, so stripping a shared
/// prefix never cuts mid-token (`Episode 1` vs `Episode 10` keeps `10`).
final RegExp _prefixBoundary = RegExp(r'[\s\p{P}]', unicode: true);

/// The titles' shared prefix, trimmed back to the last whitespace or
/// punctuation boundary. `Episode 1` and `Episode 10` share `Episode `, and
/// `9-nine- Episode 1` with `9-nine- NewEpisode` shares `9-nine- `.
String sharedTitlePrefix(List<String> titles) {
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
  var end = prefix.length;
  while (end > 0 && !_prefixBoundary.hasMatch(prefix[end - 1])) {
    end--;
  }
  return prefix.substring(0, end);
}

/// Collapses runs of whitespace to one space and trims the ends, so a group
/// name still matches a title with different spacing.
String _collapseWhitespace(String raw) =>
    raw.trim().replaceAll(RegExp(r'\s+'), ' ');

/// The member's short name in the episode picker: its title with the group's
/// name stripped from the start (case-insensitive, whitespace-collapsed),
/// then leading ` -:–` trimmed. The full title when it doesn't start with
/// the name, or when nothing is left.
String memberShortName(GameGroup group, Game member, Map<String, Game> byId) =>
    shortNameForGroup(group.name, member.title);

/// [memberShortName] against an explicit group name, so suggestions (which
/// have a name but no group yet) share the same rule.
String shortNameForGroup(String groupName, String title) {
  final name = _collapseWhitespace(groupName);
  if (name.isEmpty) return title;
  final collapsed = _collapseWhitespace(title);
  if (collapsed.length <= name.length ||
      !collapsed.toLowerCase().startsWith(name.toLowerCase())) {
    return title;
  }
  final rest = collapsed
      .substring(name.length)
      .replaceFirst(RegExp(r'^[\s\-:–]+'), '');
  return rest.isEmpty ? title : rest;
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
