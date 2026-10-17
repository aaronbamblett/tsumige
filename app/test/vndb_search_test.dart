// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tsumige/src/core/vndb.dart';

String _page(List<Map<String, Object?>> rows) =>
    jsonEncode({'results': rows, 'more': false});

Map<String, Object?> _row(String id, String title,
    {String? alttitle,
    List<String> altTitles = const [],
    String? released = '2020-01-01',
    Object? rating = 85.0,
    int votecount = 42,
    String? imageUrl = 'https://t.vndb.org/sf/12/1234.jpg',
    int sexual = 0,
    String description = 'A story.',
    List<String> developers = const ['Dev Studio'],
    List<Map<String, Object?>> tags = const [
      {'name': 'Romance', 'rating': 80.0, 'spoiler': 0}
    ]}) {
  return {
    'id': id,
    'title': title,
    if (alttitle case final alt) 'alttitle': alt,
    'titles': [for (final t in altTitles) {'title': t}],
    if (released case final rel) 'released': rel,
    if (rating case final rat) 'rating': rat,
    'votecount': votecount,
    if (imageUrl != null)
      'image': {'url': imageUrl, 'sexual': sexual},
    'description': description,
    'developers': [for (final d in developers) {'name': d}],
    'tags': tags,
  };
}

void main() {
  test('sends filters, sort, results and fields', () async {
    Map<String, Object?>? seenBody;
    Map<String, String>? seenHeaders;
    final client = VndbClient(
      client: MockClient((request) async {
        seenBody = jsonDecode(request.body) as Map<String, Object?>;
        seenHeaders = request.headers;
        return http.Response(
            _page([
              _row('v1', 'DEMO', imageUrl: null),
            ]),
            200);
      }),
      retryDelay: Duration.zero,
    );
    final results = await client.search('DEMO');
    expect(seenBody!['filters'], ['search', '=', 'DEMO']);
    expect(seenBody!['sort'], 'searchrank');
    expect(seenBody!['results'], 20);
    expect(seenBody!['fields'],
        'id,title,alttitle,titles.title,released,rating,votecount,'
        'image.url,image.sexual,description,'
        'tags.name,tags.rating,tags.spoiler,developers.name');
    expect(seenHeaders!['User-Agent'], contains('tsumige/'));
    expect(results.single.id, 'v1');
    expect(results.single.title, 'DEMO');
    expect(results.single.released, '2020-01-01');
    expect(results.single.rating, 85.0);
    expect(results.single.votecount, 42);
    expect(results.single.imageUrl, isNull);
    expect(results.single.description, 'A story.');
    expect(results.single.developers, ['Dev Studio']);
    expect(results.single.tags, ['Romance']);
  });

  test('a VNDB id query uses the id filter', () async {
    final seen = <Object?>[];
    final client = VndbClient(
      client: MockClient((request) async {
        seen.add(
            (jsonDecode(request.body) as Map<String, Object?>)['filters']);
        return http.Response(_page([_row('v123', 'Some Game')]), 200);
      }),
      retryDelay: Duration.zero,
    );
    await client.search('v123');
    await client.search('https://vndb.org/v456');
    await client.search('  V789  ');
    expect(seen, [
      ['id', '=', 'v123'],
      ['id', '=', 'v456'],
      ['id', '=', 'v789'],
    ]);
  });

  test('exact-title ranking moves DEMO to the top', () async {
    final client = VndbClient(
      client: MockClient((request) async => http.Response(
          _page([
            _row('v1', 'Atriocious Tales'),
            _row('v2', 'Something Else', alttitle: 'unrelated'),
            _row('v3', 'First Light', altTitles: ['demo']),
            _row('v4', 'Demo Story -First Light-'),
          ]),
          200)),
      retryDelay: Duration.zero,
    );
    final results = await client.search('demo');
    expect([for (final r in results) r.id], ['v3', 'v1', 'v2', 'v4']);
  });

  test('spoiler tags are excluded and tags are capped at 10', () async {
    final tags = <Map<String, Object?>>[
      {'name': 'Spoilered', 'rating': 99.0, 'spoiler': 2},
      {'name': 'Major Spoiler', 'rating': 98.0, 'spoiler': 1},
      for (var i = 12; i >= 1; i--)
        {'name': 'Tag$i', 'rating': i.toDouble(), 'spoiler': 0},
    ];
    final client = VndbClient(
      client: MockClient((request) async => http.Response(
          _page([
            _row('v1', 'Tagged', tags: tags),
          ]),
          200)),
      retryDelay: Duration.zero,
    );
    final tagsOut = (await client.search('Tagged')).single.tags;
    expect(tagsOut, hasLength(10));
    expect(tagsOut, isNot(contains('Spoilered')));
    expect(tagsOut, isNot(contains('Major Spoiler')));
    expect(tagsOut.first, 'Tag12');
    expect(tagsOut.last, 'Tag3');
  });

  test('429 retried once', () async {
    var calls = 0;
    final client = VndbClient(
      client: MockClient((request) async {
        calls++;
        if (calls == 1) return http.Response('slow down', 429);
        return http.Response(
            _page([
              _row('v1', 'Patient Game'),
            ]),
            200);
      }),
      retryDelay: Duration.zero,
    );
    final results = await client.search('Patient Game');
    expect(calls, 2);
    expect(results.single.id, 'v1');
  });

  test('sexual covers and missing fields parse', () async {
    final client = VndbClient(
      client: MockClient((request) async => http.Response(
          _page([
            {
              'id': 'v9',
              'title': 'Blurry',
              'titles': [],
              'votecount': 0,
              'image': {
                'url': 'https://t.vndb.org/sf/12/nsfw.jpg',
                'sexual': 1
              },
              'description': 'x',
              'developers': [],
              'tags': [],
            },
          ]),
          200)),
      retryDelay: Duration.zero,
    );
    final result = (await client.search('Blurry')).single;
    expect(result.imageUrl, 'https://t.vndb.org/sf/12/nsfw.jpg');
    expect(result.imageSexual, 1);
    expect(result.alttitle, isNull);
    expect(result.released, isNull);
    expect(result.rating, isNull);
    expect(result.developers, isEmpty);
    expect(result.tags, isEmpty);
  });

  test('every titles.title entry parses into titles', () async {
    final client = VndbClient(
      client: MockClient((request) async => http.Response(
          _page([
            _row('v5', 'Main Title', altTitles: ['Romaji', 'Second Latin']),
          ]),
          200)),
      retryDelay: Duration.zero,
    );
    final result = (await client.search('Main Title')).single;
    expect(result.titles, ['Romaji', 'Second Latin']);
  });
}
