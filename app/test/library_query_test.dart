// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:vnl/src/constants/pref_keys.dart';
import 'package:vnl/src/core/model.dart';
import 'package:vnl/src/features/library/domain/library_query.dart';

Game game(
  String id,
  String title, {
  bool favourite = false,
  List<String> tags = const [],
  double? rating,
  DateTime? addedAt,
  List<PlaySession>? sessions,
}) =>
    Game(
      id: id,
      title: title,
      favourite: favourite,
      tags: tags,
      vndbRating: rating,
      addedAt: addedAt,
      playSessions: sessions,
    );

PlaySession session(int year, int seconds) => PlaySession(
      startedAt: DateTime.utc(year),
      durationSeconds: seconds,
    );

void main() {
  test('search is case-insensitive', () {
    final games = [
      game('a', 'Subahibi'),
      game('b', 'Something else'),
    ];
    final found = applyQuery(
      games,
      LibraryQuery(search: 'SUBA', field: SortField.title, ascending: true),
    );
    expect(found.map((g) => g.title), ['Subahibi']);
  });

  test('favourites and tag filter combine', () {
    final games = [
      game('a', 'A', favourite: true, tags: ['horror']),
      game('b', 'B', favourite: true, tags: ['comedy']),
      game('c', 'C', favourite: false, tags: ['horror']),
    ];
    final found = applyQuery(
      games,
      LibraryQuery(
        favouritesOnly: true,
        tag: 'horror',
        field: SortField.title,
        ascending: true,
      ),
    );
    expect(found.map((g) => g.title), ['A']);
  });

  test('rating nulls last both directions', () {
    final games = [
      game('a', 'A', rating: 84),
      game('b', 'B'),
      game('c', 'C', rating: 70),
    ];
    final desc = applyQuery(
      games,
      LibraryQuery(field: SortField.vndbRating, ascending: false),
    );
    expect(desc.map((g) => g.title), ['A', 'C', 'B']);
    final asc = applyQuery(
      games,
      LibraryQuery(field: SortField.vndbRating, ascending: true),
    );
    expect(asc.map((g) => g.title), ['C', 'A', 'B']);
  });

  test('last played never played last', () {
    final games = [
      game('a', 'Unplayed'),
      game('b', 'Old', sessions: [session(2020, 60)]),
      game('c', 'New', sessions: [session(2024, 60)]),
    ];
    final desc = applyQuery(
      games,
      LibraryQuery(field: SortField.lastPlayed, ascending: false),
    );
    expect(desc.map((g) => g.title), ['New', 'Old', 'Unplayed']);
    final asc = applyQuery(
      games,
      LibraryQuery(field: SortField.lastPlayed, ascending: true),
    );
    expect(asc.map((g) => g.title), ['Old', 'New', 'Unplayed']);
  });

  test('added ascending is oldest first', () {
    final games = [
      game('a', 'New', addedAt: DateTime.utc(2024)),
      game('b', 'Old', addedAt: DateTime.utc(2020)),
    ];
    final asc = applyQuery(
      games,
      LibraryQuery(field: SortField.added, ascending: true),
    );
    expect(asc.map((g) => g.title), ['Old', 'New']);
  });

  test('all tags unique sorted', () {
    expect(
      allTags([game('a', 'A', tags: ['story', 'Science', 'Story'])]),
      ['Science', 'story'],
    );
  });

  test('vndb tag filter matches rating 1.0 and up under the vndb prefix', () {
    final strong = Game(id: 'a', title: 'A', vndbTags: const [
      VndbTag(name: 'Romance', rating: 2.0, spoiler: 0, category: 'cont'),
    ]);
    final weak = Game(id: 'b', title: 'B', vndbTags: const [
      VndbTag(name: 'Romance', rating: 0.5, spoiler: 0, category: 'cont'),
    ]);
    final mine = Game(id: 'c', title: 'C', tags: ['Romance']);
    final found = applyQuery(
      [strong, weak, mine],
      const LibraryQuery(tag: 'vndb:Romance'),
    );
    expect(found.map((g) => g.id), ['a']);
  });

  test('vndbTagCounts counts non-spoiler tags at rating 2.0 and up', () {
    final games = [
      Game(id: 'a', title: 'A', vndbTags: const [
        VndbTag(name: 'Romance', rating: 2.5, spoiler: 0, category: 'cont'),
        VndbTag(name: 'Twist', rating: 2.5, spoiler: 1, category: 'cont'),
        VndbTag(name: 'Weak', rating: 1.5, spoiler: 0, category: 'cont'),
      ]),
      Game(id: 'b', title: 'B', vndbTags: const [
        VndbTag(name: 'Romance', rating: 2.0, spoiler: 0, category: 'cont'),
        VndbTag(name: 'Yuri', rating: 2.0, spoiler: 0, category: 'cont'),
      ]),
    ];
    expect(vndbTagCounts(games), [('Romance', 2), ('Yuri', 1)]);
  });
}
