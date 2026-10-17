// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:vnl/src/core/model.dart';
import 'package:vnl/src/core/vndb.dart';

final _now = DateTime.utc(2026, 10, 16, 12);

String _fixture() =>
    File('test/core/fixtures/vndb/ratings_page.json').readAsStringSync();

LoadedLibrary _library(List<(String id, String? vndbId)> games) =>
    LoadedLibrary(
        library: Library(
            games: [for (final (id, vndbId) in games) Game(id: id, vndbId: vndbId)]));

Game _byVndb(LoadedLibrary loaded, String vndbId) =>
    loaded.library.games.firstWhere((g) => g.vndbId == vndbId);

const _uuids = [
  '11111111-1111-4111-8111-111111111111',
  '22222222-2222-4222-8222-222222222222',
  '33333333-3333-4333-8333-333333333333',
];

String _page(List<Map<String, Object?>> rows) =>
    jsonEncode({'results': rows, 'more': false});

void main() {
  test('chunks of 100', () {
    final ids = [for (var i = 0; i < 218; i++) 'v$i'];
    final bodies = ratingRequestBodies(ids);
    expect(bodies, hasLength(3));
    List<String> chunkIds(Map<String, Object?> body) {
      final filters = body['filters'] as List;
      if (filters.first == 'or') {
        return [for (final f in filters.skip(1)) (f as List).last as String];
      }
      return [filters.last as String];
    }

    expect(chunkIds(bodies[0]), hasLength(100));
    expect(chunkIds(bodies[1]), hasLength(100));
    expect(chunkIds(bodies[2]), hasLength(18));
    expect(chunkIds(bodies[0]).first, 'v0');
    expect(chunkIds(bodies[2]).last, 'v217');
    for (final body in bodies) {
      expect(body['fields'], 'id,rating,votecount,released');
      expect(body['results'], 100);
    }
    final single = ratingRequestBodies(['v7']).single;
    expect(single['filters'], ['id', '=', 'v7']);
  });

  test('parses null rating', () {
    final ratings = parseRatings(_fixture());
    expect(ratings, hasLength(3));
    final unrated = ratings.firstWhere((r) => r.id == 'v199');
    expect(unrated.rating, isNull);
    expect(unrated.votecount, 0);
    expect(unrated.released, 'TBA');
    final rated = ratings.firstWhere((r) => r.id == 'v900017');
    expect(rated.rating, closeTo(84.23, 0.001));
    expect(rated.votecount, 1337);
    expect(rated.released, '2017-01-27');
  });

  test('updates and reports missing', () async {
    final loaded = _library([(_uuids[0], 'v1'), (_uuids[1], 'v2'), (_uuids[2], 'v3')]);
    final client = VndbClient(
      client: MockClient((request) async => http.Response(
          _page([
            {'id': 'v1', 'rating': 84.2, 'votecount': 10, 'released': '2020-01-01'},
            {'id': 'v2', 'rating': null, 'votecount': 0, 'released': 'TBA'},
          ]),
          200)),
      retryDelay: Duration.zero,
    );
    final report = await refreshRatings(loaded, client, now: _now);
    expect(report.error, isNull);
    expect(report.updated, 2);
    expect(report.notFound, ['v3']);
    expect(_byVndb(loaded, 'v1').vndbRating, 84.2);
    expect(_byVndb(loaded, 'v1').vndbVotecount, 10);
    expect(_byVndb(loaded, 'v1').released, '2020-01-01');
    expect(_byVndb(loaded, 'v1').vndbFetchedAt, _now);
    expect(_byVndb(loaded, 'v2').vndbRating, isNull);
    expect(_byVndb(loaded, 'v3').vndbRating, isNull);
    expect(_byVndb(loaded, 'v3').vndbFetchedAt, isNull);
  });

  test('failure keeps old values', () async {
    final loaded = _library([(_uuids[0], 'v1')]);
    final game = _byVndb(loaded, 'v1');
    game.vndbRating = 84.2;
    game.vndbVotecount = 9;
    game.released = '2019-05-05';
    final fetchedAt = DateTime.utc(2026, 1, 1);
    game.vndbFetchedAt = fetchedAt;
    final client = VndbClient(
      client: MockClient((request) async => http.Response('boom', 500)),
      retryDelay: Duration.zero,
    );
    final report = await refreshRatings(loaded, client, now: _now);
    expect(report.error, isNotNull);
    expect(report.notFound, isEmpty);
    expect(game.vndbRating, 84.2);
    expect(game.vndbVotecount, 9);
    expect(game.released, '2019-05-05');
    expect(game.vndbFetchedAt, fetchedAt);
  });

  test('429 retried once', () async {
    var calls = 0;
    final client = VndbClient(
      client: MockClient((request) async {
        calls++;
        if (calls == 1) return http.Response('slow down', 429);
        return http.Response(
            _page([
              {'id': 'v1', 'rating': 70, 'votecount': 5, 'released': '2021'},
            ]),
            200);
      }),
      retryDelay: Duration.zero,
    );
    final loaded = _library([(_uuids[0], 'v1')]);
    final report = await refreshRatings(loaded, client, now: _now);
    expect(calls, 2);
    expect(report.error, isNull);
    expect(report.updated, 1);
    expect(_byVndb(loaded, 'v1').vndbRating, 70.0);
  });

  test('partial success keeps earlier chunk values', () async {
    final ids = [for (var i = 0; i < 101; i++) 'v$i'];
    final loaded = _library([
      for (var i = 0; i < ids.length; i++)
        ('00000000-0000-4000-8000-${i.toString().padLeft(12, '0')}', ids[i]),
    ]);
    final lateGame = _byVndb(loaded, 'v100');
    lateGame.vndbRating = 60.0;
    var calls = 0;
    final client = VndbClient(
      client: MockClient((request) async {
        calls++;
        if (calls == 1) {
          return http.Response(
              _page([
                for (var i = 0; i < 100; i++)
                  {
                    'id': 'v$i',
                    'rating': 80,
                    'votecount': 1,
                    'released': '2020',
                  },
              ]),
              200);
        }
        return http.Response('boom', 500);
      }),
      retryDelay: Duration.zero,
    );
    final report = await refreshRatings(loaded, client, now: _now);
    expect(report.error, isNotNull);
    expect(report.notFound, isEmpty);
    expect(_byVndb(loaded, 'v0').vndbRating, 80.0);
    expect(_byVndb(loaded, 'v0').vndbFetchedAt, _now);
    expect(lateGame.vndbRating, 60.0);
    expect(lateGame.vndbFetchedAt, isNull);
  });

  test('fetchCoverUrl returns image.url', () async {
    Map<String, Object?>? seen;
    final client = VndbClient(
      client: MockClient((request) async {
        seen = jsonDecode(request.body) as Map<String, Object?>;
        return http.Response(
            _page([
              {
                'id': 'v900017',
                'image': {'url': 'https://t.vndb.org/sf/12/1234.jpg'}
              },
            ]),
            200);
      }),
      retryDelay: Duration.zero,
    );
    expect(await client.fetchCoverUrl('v900017'),
        'https://t.vndb.org/sf/12/1234.jpg');
    expect(seen!['filters'], ['id', '=', 'v900017']);
    expect(seen!['fields'], 'id,image.url');
  });

  test('fetchCoverUrl is null without an image', () async {
    final client = VndbClient(
      client: MockClient((request) async =>
          http.Response(_page([]), 200)),
      retryDelay: Duration.zero,
    );
    expect(await client.fetchCoverUrl('v404'), isNull);
    final noImage = VndbClient(
      client: MockClient((request) async => http.Response(
          _page([
            {'id': 'v1'}
          ]),
          200)),
      retryDelay: Duration.zero,
    );
    expect(await noImage.fetchCoverUrl('v1'), isNull);
  });

  test('deduplicates ids and skips games without vndbId', () async {
    final seen = <Map<String, Object?>>[];
    final client = VndbClient(
      client: MockClient((request) async {
        seen.add(jsonDecode(request.body) as Map<String, Object?>);
        return http.Response(
            _page([
              {'id': 'v1', 'rating': 90, 'votecount': 3, 'released': '2022-02'},
            ]),
            200);
      }),
      retryDelay: Duration.zero,
    );
    final loaded = _library([(_uuids[0], 'v1'), (_uuids[1], 'v1'), (_uuids[2], null)]);
    final report = await refreshRatings(loaded, client, now: _now);
    expect(seen, hasLength(1));
    expect(report.error, isNull);
    expect(report.updated, 2);
    expect(report.notFound, isEmpty);
  });
}
