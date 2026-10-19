// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../features/library/domain/add_game.dart';
import '../utils/prefs/app_prefs.dart';
import 'version.dart';
import 'vndb.dart';

part 'steamgriddb.g.dart';

const String steamGridDbApi = 'https://www.steamgriddb.com/api/v2';
const String steamGridDbPreferencesUrl =
    'https://www.steamgriddb.com/profile/preferences';

/// Normalizes a game title for the SteamGridDB exact-match preselect:
/// lowercase, alphanumerics only.
String normalizeGridTitle(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

class SteamGridDbException implements Exception {
  final String message;

  const SteamGridDbException(this.message);

  @override
  String toString() => 'SteamGridDbException: $message';
}

class SteamGridDbBadKeyException extends SteamGridDbException {
  const SteamGridDbBadKeyException() : super('bad key');
}

class SteamGridDbGame {
  final int id;
  final String name;

  const SteamGridDbGame({required this.id, required this.name});
}

const String _gridQuery =
    'dimensions=600x900,342x482,660x930&types=static&nsfw=false&humor=false';

const String _heroQuery =
    'dimensions=1920x620,3840x1240,1600x650&types=static&nsfw=false&humor=false';

class SteamGridDbClient {
  final String apiKey;
  final http.Client _client;
  final String baseUrl;

  SteamGridDbClient({
    required this.apiKey,
    http.Client? client,
    this.baseUrl = steamGridDbApi,
  }) : _client = client ?? http.Client();

  Map<String, String> get _realHeaders => {
    'Authorization': 'Bearer $apiKey',
    'User-Agent': 'tsumige/$appVersion',
  };

  Future<http.Response> _get(Uri uri) async {
    try {
      return await _client.get(uri, headers: _realHeaders);
    } catch (e) {
      throw SteamGridDbException('request failed');
    }
  }

  Never _throwForStatus(int status) {
    if (status == 401 || status == 403) {
      throw const SteamGridDbBadKeyException();
    }
    throw SteamGridDbException('HTTP $status');
  }

  List<ArtCandidate> _parseGrids(Object? decoded) {
    if (decoded is! Map) {
      throw const SteamGridDbException('unexpected response shape');
    }
    final data = decoded['data'];
    if (data is! List) {
      throw const SteamGridDbException('unexpected response shape');
    }
    final out = <ArtCandidate>[];
    for (final entry in data) {
      if (entry is! Map) continue;
      final url = entry['url'];
      if (url is! String || !url.startsWith('http')) continue;
      final thumb = entry['thumb'];
      out.add(
        ArtCandidate(
          url: url,
          thumbnail: thumb is String && thumb.startsWith('http')
              ? thumb
              : url,
          width: entry['width'] is int ? entry['width'] as int : 0,
          height: entry['height'] is int ? entry['height'] as int : 0,
          type: 'steamgriddb',
        ),
      );
    }
    return out;
  }

  Object? _decode(http.Response response) {
    try {
      return jsonDecode(response.body);
    } catch (_) {
      throw const SteamGridDbException('invalid JSON');
    }
  }

  Future<List<ArtCandidate>> gridsForSteamApp(int appId) async {
    final uri = Uri.parse('$baseUrl/grids/steam/$appId?$_gridQuery');
    final response = await _get(uri);
    if (response.statusCode == 404) return const [];
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwForStatus(response.statusCode);
    }
    return _parseGrids(_decode(response));
  }

  Future<List<SteamGridDbGame>> searchGames(String term) async {
    final uri = Uri.parse(
      '$baseUrl/search/autocomplete/${Uri.encodeComponent(term.trim())}',
    );
    final response = await _get(uri);
    if (response.statusCode == 404) return const [];
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwForStatus(response.statusCode);
    }
    final decoded = _decode(response);
    if (decoded is! Map || decoded['data'] is! List) {
      throw const SteamGridDbException('unexpected response shape');
    }
    final out = <SteamGridDbGame>[];
    for (final entry in decoded['data'] as List) {
      if (entry is! Map) continue;
      final id = entry['id'];
      final name = entry['name'];
      if (id is! int || name is! String) continue;
      out.add(SteamGridDbGame(id: id, name: name));
      if (out.length >= 6) break;
    }
    return out;
  }

  Future<List<ArtCandidate>> gridsForGame(int gameId) async {
    final uri = Uri.parse('$baseUrl/grids/game/$gameId?$_gridQuery');
    final response = await _get(uri);
    if (response.statusCode == 404) return const [];
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwForStatus(response.statusCode);
    }
    return _parseGrids(_decode(response));
  }

  Future<List<ArtCandidate>> heroesForSteamApp(int appId) async {
    final uri = Uri.parse('$baseUrl/heroes/steam/$appId?$_heroQuery');
    final response = await _get(uri);
    if (response.statusCode == 404) return const [];
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwForStatus(response.statusCode);
    }
    return _parseGrids(_decode(response));
  }

  Future<List<ArtCandidate>> heroesForGame(int gameId) async {
    final uri = Uri.parse('$baseUrl/heroes/game/$gameId?$_heroQuery');
    final response = await _get(uri);
    if (response.statusCode == 404) return const [];
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwForStatus(response.statusCode);
    }
    return _parseGrids(_decode(response));
  }
}

/// SteamGridDB client built from the stored key, or null when no key is set.
/// Shares the overridable HTTP client the picker uses, so tests can fake it.
@riverpod
SteamGridDbClient? steamGridDbClient(Ref ref) {
  final key = ref.watch(steamGridDbKeyProvider);
  if (key.trim().isEmpty) return null;
  return SteamGridDbClient(
    apiKey: key.trim(),
    client: ref.watch(addGameHttpClientProvider),
  );
}
