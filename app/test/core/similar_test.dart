// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:vnl/src/core/model.dart';
import 'package:vnl/src/core/similar.dart';

VndbTag _tag(
  String name,
  double rating, {
  int spoiler = 0,
  String category = 'cont',
}) => VndbTag(name: name, rating: rating, spoiler: spoiler, category: category);

Game _game(
  String id, {
  String? vndbId,
  List<VndbTag> tags = const [],
  List<VnRelation> relations = const [],
}) => Game(id: id, vndbId: vndbId, vndbTags: tags, relations: relations);

void main() {
  final target = _game(
    'target',
    vndbId: 'v1',
    tags: [
      _tag('loop', 2.0),
      _tag('mystery', 1.5),
      _tag('weak', 1.0),
      _tag('secret', 2.0, spoiler: 1),
      _tag('ntr', 2.0, category: 'ero'),
      _tag('voiced', 2.0, category: 'tech'),
    ],
    relations: [
      const VnRelation(
        vndbId: 'v9',
        relation: 'seq',
        title: 'Sibling',
        official: true,
      ),
    ],
  );

  test('ranks by cosine over content tags, best first', () {
    final library = [
      _game(
        'far',
        vndbId: 'v2',
        tags: [_tag('loop', 2.0), _tag('romance', 3.0)],
      ),
      _game(
        'close',
        vndbId: 'v3',
        tags: [_tag('loop', 2.0), _tag('mystery', 1.5)],
      ),
      _game('none', vndbId: 'v4', tags: [_tag('romance', 3.0)]),
    ];
    final ranked = similarGames(target, library);
    expect([for (final (game, _) in ranked) game.id], ['close', 'far']);
    expect(ranked.first.$2, closeTo(1.0, 1e-9));
    expect(ranked.last.$2, closeTo(4.0 / (2.5 * sqrt(13)), 1e-9));
  });

  test('excludes the target itself and its relations', () {
    final library = [
      target,
      _game('sibling', vndbId: 'v9', tags: [_tag('loop', 2.0)]),
      _game('other', vndbId: 'v3', tags: [_tag('loop', 2.0)]),
    ];
    final ranked = similarGames(target, library);
    expect([for (final (game, _) in ranked) game.id], ['other']);
  });

  test('spoiler, tech, ero and weak tags are ignored', () {
    final library = [
      _game(
        'spoilers',
        vndbId: 'v5',
        tags: [
          _tag('secret', 2.0),
          _tag('ntr', 2.0, category: 'cont'),
          _tag('voiced', 2.0, category: 'tech'),
          _tag('weak', 2.0),
        ],
      ),
      _game('weakonly', vndbId: 'v6', tags: [_tag('mystery', 1.0)]),
    ];
    expect(similarGames(target, library), isEmpty);
  });

  test('games without tags are left out', () {
    final library = [_game('untagged', vndbId: 'v7')];
    expect(similarGames(target, library), isEmpty);
  });

  test('a target without content tags ranks nothing', () {
    final untagged = _game('lonely', vndbId: 'v8');
    final library = [
      _game('a', vndbId: 'v3', tags: [_tag('loop', 2.0)]),
    ];
    expect(similarGames(untagged, library), isEmpty);
  });

  test('limit caps the result', () {
    final library = [
      _game('a', vndbId: 'v3', tags: [_tag('loop', 2.0), _tag('mystery', 1.5)]),
      _game('b', vndbId: 'v4', tags: [_tag('loop', 1.0)]),
    ];
    final ranked = similarGames(target, library, limit: 1);
    expect([for (final (game, _) in ranked) game.id], ['a']);
  });
}
