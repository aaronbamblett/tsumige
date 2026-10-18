// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tsumige/src/core/steamgriddb.dart';
import 'package:tsumige/src/core/version.dart';
import 'package:tsumige/src/core/vndb.dart';

const _key = 'fake-test-key';

String _gridsBody(List<String> urls) => jsonEncode({
  'success': true,
  'data': [
    for (var i = 0; i < urls.length; i++)
      {
        'id': i + 1,
        'width': 600,
        'height': 900,
        'url': urls[i],
        'thumb': '${urls[i]}-thumb',
        'nsfw': false,
        'humor': false,
        'mime': 'image/jpeg',
      },
  ],
});

SteamGridDbClient _client(Future<http.Response> Function(http.Request) fn) =>
    SteamGridDbClient(apiKey: _key, client: MockClient(fn));

void main() {
  test('gridsForSteamApp sends the right URL and headers', () async {
    http.Request? seen;
    final client = _client((request) async {
      seen = request;
      return http.Response(_gridsBody(['https://example.com/a.jpg']), 200);
    });
    final grids = await client.gridsForSteamApp(123);
    expect(grids, hasLength(1));
    expect(grids.single.url, 'https://example.com/a.jpg');
    expect(grids.single.thumbnail, 'https://example.com/a.jpg-thumb');
    expect(grids.single.width, 600);
    expect(grids.single.height, 900);
    expect(grids.single.type, 'steamgriddb');
    final uri = seen!.url;
    expect(uri.host, 'www.steamgriddb.com');
    expect(uri.path, '/api/v2/grids/steam/123');
    expect(uri.query, contains('dimensions=600x900,342x482,660x930'));
    expect(uri.query, contains('types=static'));
    expect(uri.query, contains('nsfw=false'));
    expect(uri.query, contains('humor=false'));
    expect(seen!.headers['Authorization'], 'Bearer $_key');
    expect(seen!.headers['User-Agent'], 'tsumige/$appVersion');
  });

  test('gridsForSteamApp merges nothing here: 404 means empty', () async {
    final client = _client((_) async => http.Response('nope', 404));
    expect(await client.gridsForSteamApp(999), isEmpty);
  });

  test('401 means a bad key', () async {
    final client = _client((_) async => http.Response('unauthorized', 401));
    expect(
      client.gridsForSteamApp(123),
      throwsA(isA<SteamGridDbBadKeyException>()),
    );
    expect(
      client.searchGames('x'),
      throwsA(isA<SteamGridDbBadKeyException>()),
    );
    expect(
      client.gridsForGame(7),
      throwsA(isA<SteamGridDbBadKeyException>()),
    );
  });

  test('a network failure keeps the key out of the error', () async {
    final client = _client((_) async => throw TimeoutException('down'));
    for (final future in [
      client.gridsForSteamApp(123),
      client.searchGames('x'),
      client.gridsForGame(7),
    ]) {
      try {
        await future;
        fail('expected an error');
      } catch (e) {
        expect('$e', isNot(contains(_key)));
      }
    }
    final bad = _client((_) async => http.Response('denied', 401));
    try {
      await bad.gridsForSteamApp(1);
      fail('expected a bad-key error');
    } catch (e) {
      expect('$e', isNot(contains(_key)));
    }
  });

  test('searchGames returns at most 6 id/name pairs', () async {
    http.Request? seen;
    final client = _client((request) async {
      seen = request;
      return http.Response(
        jsonEncode({
          'data': [
            for (var i = 0; i < 8; i++) {'id': i, 'name': 'Game $i'},
          ],
        }),
        200,
      );
    });
    final results = await client.searchGames('DiviDead');
    expect(results, hasLength(6));
    expect(results.first.id, 0);
    expect(results.first.name, 'Game 0');
    expect(seen!.url.path, '/api/v2/search/autocomplete/DiviDead');
    expect(seen!.headers['Authorization'], 'Bearer $_key');
  });

  test('gridsForGame hits the game endpoint', () async {
    http.Request? seen;
    final client = _client((request) async {
      seen = request;
      return http.Response(_gridsBody(['https://example.com/g.jpg']), 200);
    });
    final grids = await client.gridsForGame(42);
    expect(grids.single.url, 'https://example.com/g.jpg');
    expect(seen!.url.path, '/api/v2/grids/game/42');
    expect(seen!.url.query, contains('dimensions='));
  });

  test('normalizeGridTitle matches DiviDead to Divi-Dead', () {
    expect(normalizeGridTitle('DiviDead'), normalizeGridTitle('Divi-Dead'));
    expect(normalizeGridTitle('White Album 2'), 'whitealbum2');
  });

  group('fetchSteamAppIds', () {
    VndbClient vndbFor(List<Map<String, Object?>> releases) => VndbClient(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/release')) {
          return http.Response(
            jsonEncode({'results': releases, 'more': false}),
            200,
          );
        }
        return http.Response(jsonEncode({'results': [], 'more': false}), 200);
      }),
      retryDelay: Duration.zero,
    );

    test('sends the extlink filter and fields', () async {
      Map<String, Object?>? seen;
      final client = VndbClient(
        client: MockClient((request) async {
          seen = jsonDecode(request.body) as Map<String, Object?>;
          return http.Response(
            jsonEncode({'results': [], 'more': false}),
            200,
          );
        }),
        retryDelay: Duration.zero,
      );
      await client.fetchSteamAppIds('v123');
      expect(seen!['filters'], [
        'and',
        ['vn', '=', ['id', '=', 'v123']],
        ['extlink', '=', 'steam'],
      ]);
      expect(seen!['fields'], 'extlinks.name,extlinks.id');
    });

    test('parses string and int ids and de-duplicates', () async {
      final client = vndbFor([
        {
          'extlinks': [
            {'name': 'steam', 'id': '100'},
            {'name': 'website', 'id': 'https://example.com'},
            {'name': 'steam', 'id': 200},
          ],
        },
        {
          'extlinks': [
            {'name': 'steam', 'id': 100},
            {'name': 'steam', 'id': 'not-a-number'},
          ],
        },
      ]);
      expect(await client.fetchSteamAppIds('v1'), [100, 200]);
    });
  });
}
