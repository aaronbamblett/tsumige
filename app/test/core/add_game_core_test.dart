// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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

  test('fillVndbMetadata fills the VNDB fields', () async {
    final now = DateTime.utc(2026, 10, 17, 12);
    final client = VndbClient(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/release')) {
          return http.Response(
              jsonEncode({
                'results': [
                  {'vns': [
                    {'id': 'v900017'}
                  ]}
                ],
                'more': false,
              }),
              200);
        }
        return http.Response.bytes(
          utf8.encode(File('test/core/fixtures/vndb/vn_data_page.json')
              .readAsStringSync()),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
      retryDelay: Duration.zero,
    );
    final game = gameFromVn(_result(), exe: '/games/demo/run.exe', now: now);
    await fillVndbMetadata(game, client, now: now);
    expect(game.vndbOriginalTitle, 'デモストーリー -First Light-');
    expect(game.developers.map((d) => d.name), ['Sample Studio', 'Overseas']);
    expect(game.lengthMinutes, 1200);
    expect(game.lengthVotes, 88);
    expect(game.originalLanguage, 'ja');
    expect(game.vndbTags.map((t) => t.name), ['Romance', 'Time Loop', 'Long Text']);
    expect(game.relations.first.vndbId, 'v18');
    expect(game.adultVndb, isTrue);
    expect(game.isAdult, isTrue);
    expect(game.vndbDataFetchedAt, now);
    expect(game.tags, ['Romance', 'Sci-fi']);
  });

  test('fillVndbMetadata keeps the basic fields when VNDB fails', () async {
    final client = VndbClient(
      client: MockClient((request) async => http.Response('boom', 500)),
      retryDelay: Duration.zero,
    );
    final game = gameFromVn(_result(), exe: '/games/demo/run.exe');
    await fillVndbMetadata(game, client);
    expect(game.title, 'DEMO');
    expect(game.vndbRating, 84.2);
    expect(game.vndbOriginalTitle, isNull);
    expect(game.developers, isEmpty);
    expect(game.vndbTags, isEmpty);
    expect(game.adultVndb, isNull);
    expect(game.vndbDataFetchedAt, isNull);
  });

  test('parseTagsField trims, drops empties and dedupes', () {
    expect(parseTagsField('Romance, sci-fi ,Romance,,  '),
        ['Romance', 'sci-fi']);
    expect(parseTagsField(''), isEmpty);
  });
}
