// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:vnl/src/core/model.dart';
import 'package:vnl/src/core/vndb.dart';
import 'package:vnl/src/features/library/domain/add_game.dart';

VnSearchResult _result() => const VnSearchResult(
      id: 'v900017',
      title: 'DEMO',
      alttitle: 'Demo',
      released: '2020-06-19',
      rating: 84.2,
      votecount: 1337,
      imageUrl: 'https://t.vndb.org/sf/12/1234.jpg',
      description: 'A story.',
      developers: ['Sample Studio'],
      tags: ['Romance', 'Sci-fi'],
    );

void main() {
  test('gameFromVn maps every field', () {
    final now = DateTime.utc(2026, 10, 17, 12);
    final game = gameFromVn(_result(),
        exe: '/games/demo/run.exe', mode: LaunchMode.proton, now: now);
    expect(Uuid.isValidUUID(fromString: game.id), isTrue);
    expect(game.title, 'DEMO');
    expect(game.addedAt, now);
    expect(game.vndbId, 'v900017');
    expect(game.released, '2020-06-19');
    expect(game.vndbRating, 84.2);
    expect(game.vndbVotecount, 1337);
    expect(game.vndbFetchedAt, now);
    expect(game.description, 'A story.');
    expect(game.tags, ['Romance', 'Sci-fi']);
    expect(game.launch.executable, '/games/demo/run.exe');
    expect(game.launch.mode, LaunchMode.proton);
  });

  test('gameFromVn leaves mode unset when none is given', () {
    final game =
        gameFromVn(_result(), exe: '/games/demo/run.exe');
    expect(game.launch.mode, isNull);
    expect(game.launch.executable, '/games/demo/run.exe');
  });

  test('parseTagsField trims, drops empties and dedupes', () {
    expect(parseTagsField('Romance, sci-fi ,Romance,,  '),
        ['Romance', 'sci-fi']);
    expect(parseTagsField(''), isEmpty);
  });
}
