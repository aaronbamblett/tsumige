// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumige/src/core/group_detection.dart';
import 'package:tsumige/src/core/model.dart';

Game game(
  String id,
  String title, {
  String? vndbId,
  List<VnRelation>? relations,
}) =>
    Game(
      id: id,
      title: title,
      vndbId: vndbId,
      relations: relations,
    );

VnRelation relation(String vndbId, {String relation = 'seq'}) => VnRelation(
      vndbId: vndbId,
      relation: relation,
      title: '',
      official: true,
    );

List<Game> nineNine() => [
      game('e1', '9-nine- Episode 1',
          vndbId: 'v19829', relations: [relation('v21668')]),
      game('e2', '9-nine- Episode 2',
          vndbId: 'v21668', relations: [relation('v23740')]),
      game('e3', '9-nine- Episode 3',
          vndbId: 'v23740', relations: [relation('v26523')]),
      game('e4', '9-nine- Episode 4',
          vndbId: 'v26523', relations: [relation('v29724')]),
      game('new', '9-nine- NewEpisode', vndbId: 'v29724'),
    ];

void main() {
  test('suggests Higurashi chapters across VNDB ids', () {
    const titles = [
      'Higurashi When They Cry Hou - Ch.1 Onikakushi',
      'Higurashi When They Cry Hou - Ch.2 Watanagashi',
      'Higurashi When They Cry Hou - Ch.3 Tatarigoroshi',
      'Higurashi When They Cry Hou - Ch.4 Himatsubushi',
      'Higurashi When They Cry Hou - Ch.5 Meakashi',
      'Higurashi When They Cry Hou - Ch.6 Tsumihoroboshi',
      'Higurashi When They Cry Hou - Ch.7 Minagoroshi',
      'Higurashi When They Cry Hou - Ch.8 Matsuribayashi',
    ];
    final games = <Game>[
      for (var i = 0; i < 4; i++)
        game('h${i + 1}', titles[i],
            vndbId: 'v67',
            relations: i == 0 ? [relation('v68')] : null),
      for (var i = 4; i < 8; i++)
        game('h${i + 1}', titles[i], vndbId: 'v68'),
      game('hrei', 'Higurashi When They Cry Hou - Rei',
          vndbId: 'v69', relations: [relation('v67', relation: 'side')]),
    ];

    final suggestion = suggestGroups(Library(games: games)).single;

    expect(suggestion.name, 'Higurashi When They Cry Hou');
    expect(suggestion.memberIds,
        ['h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'h7', 'h8']);
    expect(suggestion.reason, 'both');
  });

  test('suggests numbered 9-nine- episodes but not NewEpisode', () {
    final suggestion = suggestGroups(Library(games: nineNine())).single;

    expect(suggestion.name, '9-nine-');
    expect(suggestion.memberIds, ['e1', 'e2', 'e3', 'e4']);
    expect(suggestion.reason, 'sequelChain');
  });

  test('orders Grisaia volumes with 5.5 between 5 and 6', () {
    const numbers = ['1', '2', '3', '4', '5', '5.5', '6', '7', '8'];
    const ids = ['g1', 'g2', 'g3', 'g4', 'g5', 'g55', 'g6', 'g7', 'g8'];
    final games = <Game>[
      for (var i = 0; i < numbers.length; i++)
        game(
          ids[i],
          'Grisaia Phantom Trigger Vol.${numbers[i]}',
          vndbId: 'v${100 + i}',
          relations: i + 1 < numbers.length ? [relation('v${101 + i}')] : null,
        ),
    ];

    final suggestion = suggestGroups(Library(games: games)).single;

    expect(suggestion.name, 'Grisaia Phantom Trigger');
    expect(suggestion.memberIds, ids);
    expect(suggestion.reason, 'sequelChain');
  });

  test('never suggests a pure sequel', () {
    final games = [
      game('sg', 'Steins;Gate',
          vndbId: 'v2002', relations: [relation('v17102')]),
      game('sg0', 'Steins;Gate 0', vndbId: 'v17102'),
    ];

    expect(suggestGroups(Library(games: games)), isEmpty);
  });

  test('does not join a shared VNDB id with different prefixes', () {
    final games = [
      game('foo', 'Foo Episode 1', vndbId: 'v1'),
      game('bar', 'Bar Episode 1', vndbId: 'v1'),
    ];

    expect(suggestGroups(Library(games: games)), isEmpty);
  });

  test('does not suggest when only one game has a part marker', () {
    final games = [
      game('a', 'Foo Episode 1',
          vndbId: 'v1', relations: [relation('v2')]),
      game('b', 'Foo Side Story', vndbId: 'v2'),
    ];

    expect(suggestGroups(Library(games: games)), isEmpty);
  });

  test('never suggests bare trailing numbers', () {
    final games = [
      game('a', 'Foo 1', vndbId: 'v1'),
      game('b', 'Foo 2', vndbId: 'v1'),
    ];

    expect(suggestGroups(Library(games: games)), isEmpty);
  });

  test('excludes games already in a group', () {
    final library = Library(
      games: nineNine(),
      groups: [
        GameGroup(id: 'gr1', name: '9-nine-', memberIds: ['e4', 'new']),
      ],
    );

    final suggestion = suggestGroups(library).single;

    expect(suggestion.memberIds, ['e1', 'e2', 'e3']);
  });

  test('drops a dismissed suggestion by key', () {
    final library = Library(games: nineNine());
    final suggestion = suggestGroups(library).single;

    expect(suggestion.key, 'e1,e2,e3,e4');
    expect(suggestGroups(library, dismissed: {suggestion.key}), isEmpty);
  });
}
