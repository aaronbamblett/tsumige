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
    File('test/core/fixtures/vndb/vn_data_page.json').readAsStringSync();

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

String _page(List<Map<String, Object?>> rows, {bool more = false}) =>
    jsonEncode({'results': rows, 'more': more});

/// Answers `/vn` and `/release` requests separately.
VndbClient _routed({
  required http.Response Function(Map<String, Object?> body) vn,
  http.Response Function(Map<String, Object?> body)? release,
  List<Map<String, Object?>>? seen,
}) =>
    VndbClient(
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, Object?>;
        seen?.add(body);
        if (request.url.path.endsWith('/release')) {
          return (release ?? (_) => http.Response(_page([]), 200))(body);
        }
        return vn(body);
      }),
      retryDelay: Duration.zero,
    );

http.Response _ok(List<Map<String, Object?>> rows) =>
    http.Response(_page(rows), 200);

http.Response _fixtureResponse() => http.Response.bytes(
      utf8.encode(_fixture()),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  test('fetchVnData sends the field list and chunks by 100', () async {
    final seen = <Map<String, Object?>>[];
    final client = _routed(
      vn: (body) => _ok([]),
      seen: seen,
    );
    final ids = [for (var i = 0; i < 101; i++) 'v$i'];
    await client.fetchVnData(ids);
    expect(seen, hasLength(2));
    final first = seen[0]['filters'] as List;
    expect(first.first, 'or');
    expect(first, hasLength(101));
    expect((first[1] as List).last, 'v0');
    expect((first.last as List).last, 'v99');
    expect(seen[1]['filters'], ['id', '=', 'v100']);
    for (final body in seen) {
      final fields = body['fields'] as String;
      expect(fields, contains('length_minutes,length_votes'));
      expect(fields, contains('olang,developers{id,name,original}'));
      expect(fields, contains('tags{name,rating,spoiler,category}'));
      expect(fields,
          contains('relations{id,relation,relation_official,title,image.url}'));
      expect(body['results'], 100);
    }
  });

  test('fetchVnData paginates on more', () async {
    final seen = <Map<String, Object?>>[];
    final client = _routed(
      vn: (body) => body['page'] == 1
          ? http.Response(_page([{'id': 'v1'}], more: true), 200)
          : http.Response(_page([{'id': 'v2'}]), 200),
      seen: seen,
    );
    final vns = await client.fetchVnData(['v1', 'v2']);
    expect([for (final vn in vns) vn.id], ['v1', 'v2']);
    expect([for (final body in seen) body['page']], [1, 2]);
  });

  test('fetchVnData maps every field from a sample page', () async {
    final client = _routed(
      vn: (body) => _fixtureResponse(),
    );
    final vns = await client.fetchVnData(['v900017', 'v199']);
    final demo = vns.firstWhere((v) => v.id == 'v900017');
    expect(demo.title, 'Demo Story -First Light-');
    expect(demo.alttitle, 'デモストーリー -First Light-');
    expect(demo.rating, closeTo(84.23, 0.001));
    expect(demo.votecount, 1337);
    expect(demo.released, '2017-01-27');
    expect(demo.lengthMinutes, 1200);
    expect(demo.lengthVotes, 88);
    expect(demo.olang, 'ja');

    expect(demo.developers, hasLength(2));
    expect(demo.developers.first.id, 'p1');
    expect(demo.developers.first.name, 'Sample Studio');
    expect(demo.developers.first.original, 'サンプルスタジオ');
    expect(demo.developers.last.original, isNull);

    expect([for (final t in demo.tags) t.name],
        ['Romance', 'Time Loop', 'Long Text']);
    final romance = demo.tags.first;
    expect(romance.rating, 2.5);
    expect(romance.spoiler, 0);
    expect(romance.category, 'cont');
    final loop = demo.tags[1];
    expect(loop.spoiler, 2);
    expect(loop.category, 'cont');
    expect(demo.tags.last.category, 'tech');

    expect(demo.relations, hasLength(2));
    final sequel = demo.relations.first;
    expect(sequel.vndbId, 'v18');
    expect(sequel.relation, 'seq');
    expect(sequel.title, 'Sequel');
    expect(sequel.imageUrl, 'https://t.vndb.org/cv/18.jpg');
    expect(sequel.official, isTrue);
    final alt = demo.relations.last;
    expect(alt.vndbId, 'v19');
    expect(alt.imageUrl, isNull);
    expect(alt.official, isFalse);

    final unrated = vns.firstWhere((v) => v.id == 'v199');
    expect(unrated.rating, isNull);
    expect(unrated.votecount, 0);
    expect(unrated.released, 'TBA');
    expect(unrated.lengthMinutes, isNull);
    expect(unrated.alttitle, isNull);
    expect(unrated.developers, isEmpty);
    expect(unrated.tags, isEmpty);
    expect(unrated.relations, isEmpty);
  });

  test('fetchAdultVnIds sends has_ero and maps to the id set', () async {
    final seen = <Map<String, Object?>>[];
    final client = _routed(
      vn: (body) => _ok([]),
      release: (body) => http.Response(
          _page([
            {
              'vns': [
                {'id': 'v1'},
                {'id': 'v9'},
              ]
            },
            {
              'vns': [
                {'id': 'v3'}
              ]
            },
          ]),
          200),
      seen: seen,
    );
    final ids = await client.fetchAdultVnIds(['v1', 'v2', 'v3']);
    expect(ids, {'v1', 'v3'});
    expect(seen.single['filters'], [
      'and',
      ['has_ero', '=', 1],
      [
        'vn',
        '=',
        ['or', ['id', '=', 'v1'], ['id', '=', 'v2'], ['id', '=', 'v3']]
      ],
    ]);
    expect(seen.single['fields'], 'vns.id');
  });

  test('fetchAdultVnIds uses a single id filter for one VN', () async {
    final seen = <Map<String, Object?>>[];
    final client = _routed(
      vn: (body) => _ok([]),
      release: (body) => http.Response(
          _page([
            {
              'vns': [
                {'id': 'v947549'}
              ]
            },
          ]),
          200),
      seen: seen,
    );
    expect(await client.fetchAdultVnIds(['v947549']), {'v947549'});
    expect(seen.single['filters'], [
      'and',
      ['has_ero', '=', 1],
      ['vn', '=', ['id', '=', 'v947549']],
    ]);
  });

  test('fetchAdultVnIds chunks by 100 and paginates', () async {
    final seen = <Map<String, Object?>>[];
    final client = _routed(
      vn: (body) => _ok([]),
      release: (body) {
        if (body['page'] == 1) {
          return http.Response(
              _page([
                {
                  'vns': [
                    {'id': 'v1'}
                  ]
                },
              ], more: true),
              200);
        }
        return http.Response(_page([]), 200);
      },
      seen: seen,
    );
    final ids = [for (var i = 1; i <= 101; i++) 'v$i'];
    final adult = await client.fetchAdultVnIds(ids);
    expect(adult, {'v1'});
    expect(seen, hasLength(4));
    expect([for (final body in seen) body['page']], [1, 2, 1, 2]);
    expect((seen[2]['filters'] as List).last, ['vn', '=', ['id', '=', 'v101']]);
  });

  test('fetchAdultVnIds surfaces a server error', () async {
    final client = _routed(
      vn: (body) => _ok([]),
      release: (body) => http.Response('boom', 500),
    );
    await expectLater(client.fetchAdultVnIds(['v1']),
        throwsA(isA<VndbException>()));
  });

  test('refresh fills every field and keeps adultOverride', () async {
    final loaded = _library([(_uuids[0], 'v900017'), (_uuids[1], 'v199')]);
    final override = _byVndb(loaded, 'v199');
    override.adultOverride = true;
    final client = _routed(
      vn: (body) => _fixtureResponse(),
      release: (body) => http.Response(
          _page([
            {
              'vns': [
                {'id': 'v900017'}
              ]
            },
          ]),
          200),
    );
    final report = await refreshVndbData(loaded, client,
        now: _now, gap: Duration.zero);
    expect(report.error, isNull);
    expect(report.updated, 2);
    expect(report.notFound, isEmpty);

    final demo = _byVndb(loaded, 'v900017');
    expect(demo.vndbRating, closeTo(84.23, 0.001));
    expect(demo.vndbVotecount, 1337);
    expect(demo.released, '2017-01-27');
    expect(demo.vndbOriginalTitle, 'デモストーリー -First Light-');
    expect(demo.developers, hasLength(2));
    expect(demo.lengthMinutes, 1200);
    expect(demo.lengthVotes, 88);
    expect(demo.originalLanguage, 'ja');
    expect(demo.vndbTags, hasLength(3));
    expect(demo.relations, hasLength(2));
    expect(demo.adultVndb, isTrue);
    expect(demo.isAdult, isTrue);
    expect(demo.vndbFetchedAt, _now);
    expect(demo.vndbDataFetchedAt, _now);

    expect(override.adultVndb, isFalse);
    expect(override.adultOverride, isTrue);
    expect(override.isAdult, isTrue);
    expect(override.vndbDataFetchedAt, _now);
  });

  test('refresh counts notFound', () async {
    final loaded = _library([(_uuids[0], 'v900017'), (_uuids[1], 'v404')]);
    final client = _routed(
      vn: (body) => _fixtureResponse(),
    );
    final report = await refreshVndbData(loaded, client,
        now: _now, gap: Duration.zero);
    expect(report.updated, 1);
    expect(report.notFound, ['v404']);
    expect(_byVndb(loaded, 'v404').vndbDataFetchedAt, isNull);
    expect(_byVndb(loaded, 'v404').adultVndb, isNull);
  });

  test('failure keeps old values', () async {
    final loaded = _library([(_uuids[0], 'v1')]);
    final game = _byVndb(loaded, 'v1');
    game.vndbRating = 84.2;
    game.vndbVotecount = 9;
    game.released = '2019-05-05';
    game.adultVndb = false;
    final fetchedAt = DateTime.utc(2026, 1, 1);
    game.vndbFetchedAt = fetchedAt;
    final client = _routed(vn: (body) => http.Response('boom', 500));
    final report = await refreshVndbData(loaded, client,
        now: _now, gap: Duration.zero);
    expect(report.error, isNotNull);
    expect(report.notFound, isEmpty);
    expect(game.vndbRating, 84.2);
    expect(game.vndbVotecount, 9);
    expect(game.released, '2019-05-05');
    expect(game.adultVndb, isFalse);
    expect(game.vndbFetchedAt, fetchedAt);
  });

  test('429 retried once', () async {
    var calls = 0;
    final client = _routed(vn: (body) {
      calls++;
      if (calls == 1) return http.Response('slow down', 429);
      return _ok([
        {'id': 'v1', 'rating': 70, 'votecount': 5, 'released': '2021'},
      ]);
    });
    final loaded = _library([(_uuids[0], 'v1')]);
    final report = await refreshVndbData(loaded, client,
        now: _now, gap: Duration.zero);
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
    final client = _routed(vn: (body) {
      calls++;
      if (calls == 1) {
        return _ok([
          for (var i = 0; i < 100; i++)
            {'id': 'v$i', 'rating': 80, 'votecount': 1, 'released': '2020'},
        ]);
      }
      return http.Response('boom', 500);
    });
    final report = await refreshVndbData(loaded, client,
        now: _now, gap: Duration.zero);
    expect(report.error, isNotNull);
    expect(report.notFound, isEmpty);
    expect(_byVndb(loaded, 'v0').vndbRating, 80.0);
    expect(_byVndb(loaded, 'v0').vndbFetchedAt, _now);
    expect(lateGame.vndbRating, 60.0);
    expect(lateGame.vndbFetchedAt, isNull);
  });

  test('requests are spaced by the gap', () async {
    final loaded = _library([(_uuids[0], 'v900017')]);
    final client = _routed(vn: (body) => _fixtureResponse());
    final watch = Stopwatch()..start();
    await refreshVndbData(loaded, client,
        now: _now, gap: const Duration(milliseconds: 80));
    expect(watch.elapsed, greaterThanOrEqualTo(const Duration(milliseconds: 80)));
  });

  test('fetchCoverUrl returns image.url', () async {
    Map<String, Object?>? seen;
    final client = VndbClient(
      client: MockClient((request) async {
        seen = jsonDecode(request.body) as Map<String, Object?>;
        return _ok([
          {
            'id': 'v900017',
            'image': {'url': 'https://t.vndb.org/sf/12/1234.jpg'}
          },
        ]);
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
      client: MockClient((request) async => _ok([])),
      retryDelay: Duration.zero,
    );
    expect(await client.fetchCoverUrl('v404'), isNull);
    final noImage = VndbClient(
      client: MockClient((request) async => _ok([{'id': 'v1'}])),
      retryDelay: Duration.zero,
    );
    expect(await noImage.fetchCoverUrl('v1'), isNull);
  });

  test('deduplicates ids and skips games without vndbId', () async {
    final seen = <Map<String, Object?>>[];
    final client = _routed(
      vn: (body) => _ok([
        {'id': 'v1', 'rating': 90, 'votecount': 3, 'released': '2022-02'},
      ]),
      seen: seen,
    );
    final loaded = _library([(_uuids[0], 'v1'), (_uuids[1], 'v1'), (_uuids[2], null)]);
    final report = await refreshVndbData(loaded, client,
        now: _now, gap: Duration.zero);
    expect(seen.where((b) => (b['fields'] as String).contains('tags{')), hasLength(1));
    expect(report.error, isNull);
    expect(report.updated, 2);
    expect(report.notFound, isEmpty);
  });
  group('fetchArtCandidates', () {
    const main = {
      'url': 'https://t.vndb.org/cv/16/98416.jpg',
      'thumbnail': 'https://t.vndb.org/cv.t/16/98416.jpg',
      'dims': [411, 560],
    };

    test('orders the main image, screenshots and deduped release images', () async {
      final seen = <Map<String, Object?>>[];
      final client = _routed(
        seen: seen,
        vn: (body) => _ok([
          {
            'image': main,
            'screenshots': [
              {
                'url': 'https://t.vndb.org/sf/86/101386.jpg',
                'thumbnail': 'https://t.vndb.org/sf.t/86/101386.jpg',
                'dims': [1024, 768],
              },
            ],
          },
        ]),
        release: (body) => _ok([
          {
            'images': [
              {'type': 'pkgfront', ...main},
              {
                'type': 'pkgfront',
                'url': 'https://t.vndb.org/cv/66/98366.jpg',
                'thumbnail': 'https://t.vndb.org/cv.t/66/98366.jpg',
                'dims': [350, 500],
              },
              {
                'type': 'dig',
                'url': 'https://t.vndb.org/cv/64/98364.jpg',
                'thumbnail': 'https://t.vndb.org/cv.t/64/98364.jpg',
                'dims': [1368, 770],
              },
              {
                'type': 'dig',
                'url': 'https://t.vndb.org/cv/66/98366.jpg',
                'dims': [350, 500],
              },
            ],
          },
        ]),
      );

      final art = await client.fetchArtCandidates('v927448');

      expect(art.main!.url, main['url']);
      expect(art.main!.width, 411);
      expect(art.main!.height, 560);
      expect(art.main!.type, 'main');
      expect(art.screenshots.single.type, 'screenshot');
      expect(art.screenshots.single.thumbnail,
          'https://t.vndb.org/sf.t/86/101386.jpg');
      expect(art.releaseImages.map((i) => i.url), [
        'https://t.vndb.org/cv/66/98366.jpg',
        'https://t.vndb.org/cv/64/98364.jpg',
      ]);
      expect(art.releaseImages.first.portrait, isTrue);
      expect(art.releaseImages.last.portrait, isFalse);
      expect(art.releaseImages.first.thumbnail,
          'https://t.vndb.org/cv.t/66/98366.jpg');
      expect(art.releaseImages.last.type, 'dig');
      expect(seen.first['filters'], ['id', '=', 'v927448']);
      expect(seen.last['filters'], ['vn', '=', ['id', '=', 'v927448']]);
      expect(seen.last['results'], 100);
    });

    test('falls back to the url when a thumbnail is missing', () async {
      final client = _routed(
        vn: (body) => _ok([
          {'image': {'url': 'https://t.vndb.org/cv/1/1.jpg'}},
        ]),
      );
      final art = await client.fetchArtCandidates('v1');
      expect(art.main!.thumbnail, 'https://t.vndb.org/cv/1/1.jpg');
      expect(art.main!.width, 0);
      expect(art.screenshots, isEmpty);
      expect(art.releaseImages, isEmpty);
    });

    test('pages the release request while more is set', () async {
      final pages = <Object?>[];
      final client = _routed(
        vn: (body) => _ok([{'image': main}]),
        release: (body) {
          pages.add(body['page']);
          final url = 'https://t.vndb.org/cv/${body['page']}/1.jpg';
          return http.Response(
            _page([
              {
                'images': [
                  {'type': 'dig', 'url': url, 'dims': [600, 900]},
                ],
              },
            ], more: body['page'] == 1),
            200,
          );
        },
      );
      final art = await client.fetchArtCandidates('v1');
      expect(pages, [1, 2]);
      expect(art.releaseImages.map((i) => i.url), [
        'https://t.vndb.org/cv/1/1.jpg',
        'https://t.vndb.org/cv/2/1.jpg',
      ]);
    });

    test('no VN row gives empty candidates', () async {
      final client = _routed(vn: (body) => _ok([]));
      final art = await client.fetchArtCandidates('v404');
      expect(art.main, isNull);
      expect(art.releaseImages, isEmpty);
      expect(art.screenshots, isEmpty);
    });
  });
}
