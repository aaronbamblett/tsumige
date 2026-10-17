// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:math';

import 'model.dart';

/// Library games ranked by cosine similarity of their VNDB content tags.
List<(Game, double)> similarGames(
  Game target,
  List<Game> library, {
  int limit = 6,
}) {
  final targetVector = _contentVector(target);
  if (targetVector.isEmpty) return const [];
  final related = {for (final r in target.relations) r.vndbId};
  final scored = <(Game, double)>[];
  for (final game in library) {
    if (game.id == target.id) continue;
    if (game.vndbId != null && related.contains(game.vndbId)) continue;
    final score = _cosine(targetVector, _contentVector(game));
    if (score > 0) scored.add((game, score));
  }
  scored.sort((a, b) {
    final byScore = b.$2.compareTo(a.$2);
    if (byScore != 0) return byScore;
    return library.indexOf(a.$1).compareTo(library.indexOf(b.$1));
  });
  return scored.take(limit).toList();
}

Map<String, double> _contentVector(Game game) => {
  for (final tag in game.vndbTags)
    if (tag.category == 'cont' && tag.spoiler == 0 && tag.rating >= 1.5)
      tag.name: tag.rating,
};

double _cosine(Map<String, double> a, Map<String, double> b) {
  var dot = 0.0;
  for (final entry in a.entries) {
    final other = b[entry.key];
    if (other != null) dot += entry.value * other;
  }
  if (dot == 0) return 0;
  return dot / (_norm(a) * _norm(b));
}

double _norm(Map<String, double> v) =>
    sqrt(v.values.fold(0.0, (sum, x) => sum + x * x));
