// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'model.dart';
import 'version.dart';

const String vndbApi = 'https://api.vndb.org/kana';

class VndbException implements Exception {
  final String message;

  const VndbException(this.message);

  @override
  String toString() => 'VndbException: $message';
}

class VnRating {
  final String id;
  final double? rating;
  final int votecount;
  final String? released;

  const VnRating(
      {required this.id, this.rating, this.votecount = 0, this.released});
}

class VnSearchResult {
  final String id;
  final String title;
  final String? alttitle;
  final String? released;
  final double? rating;
  final int votecount;
  final String? imageUrl;
  final int imageSexual;
  final String description;
  final List<String> developers;
  final List<String> tags;

  const VnSearchResult({
    required this.id,
    required this.title,
    this.alttitle,
    this.released,
    this.rating,
    this.votecount = 0,
    this.imageUrl,
    this.imageSexual = 0,
    this.description = '',
    List<String>? developers,
    List<String>? tags,
  })  : developers = developers ?? const [],
        tags = tags ?? const [];
}

const String _searchFields =
    'id,title,alttitle,titles.title,released,rating,votecount,'
    'image.url,image.sexual,description,'
    'tags.name,tags.rating,tags.spoiler,developers.name';

/// A VNDB id from a bare id (`v123`) or a `vndb.org/v123` URL, else null.
String? vndbIdFromQuery(String query) {
  final trimmed = query.trim();
  if (RegExp(r'^v\d+$', caseSensitive: false).hasMatch(trimmed)) {
    return trimmed.toLowerCase();
  }
  final url =
      RegExp(r'vndb\.org/v(\d+)', caseSensitive: false).firstMatch(trimmed);
  if (url != null) return 'v${url.group(1)}';
  return null;
}

// Dart has no NFKC normalizer; lowercasing covers the short ASCII titles
// searchrank buries, which is the case this ranking exists for.
String _foldTitle(String s) => s.trim().toLowerCase();

bool _titleMatches(Map raw, String foldedQuery) {
  final title = raw['title'];
  if (title is String && _foldTitle(title) == foldedQuery) return true;
  final alt = raw['alttitle'];
  if (alt is String && _foldTitle(alt) == foldedQuery) return true;
  final titles = raw['titles'];
  if (titles is List) {
    for (final entry in titles) {
      if (entry is Map &&
          entry['title'] is String &&
          _foldTitle(entry['title'] as String) == foldedQuery) {
        return true;
      }
    }
  }
  return false;
}

VnSearchResult _parseSearchResult(Map raw) {
  String? imageUrl;
  var imageSexual = 0;
  final image = raw['image'];
  if (image is Map) {
    final url = image['url'];
    if (url is String && url.startsWith('http')) imageUrl = url;
    if (image['sexual'] is int) imageSexual = image['sexual'] as int;
  }
  final developers = <String>[];
  final developersRaw = raw['developers'];
  if (developersRaw is List) {
    for (final entry in developersRaw) {
      if (entry is Map && entry['name'] is String) {
        developers.add(entry['name'] as String);
      }
    }
  }
  final scored = <(String, num)>[];
  final tagsRaw = raw['tags'];
  if (tagsRaw is List) {
    for (final entry in tagsRaw) {
      if (entry is! Map || entry['name'] is! String) continue;
      if (entry['spoiler'] is num && (entry['spoiler'] as num) != 0) continue;
      final rating = entry['rating'];
      scored.add((entry['name'] as String, rating is num ? rating : 0));
    }
  }
  scored.sort((a, b) => b.$2.compareTo(a.$2));
  final ratingRaw = raw['rating'];
  final votecountRaw = raw['votecount'];
  final releasedRaw = raw['released'];
  final alttitleRaw = raw['alttitle'];
  return VnSearchResult(
    id: raw['id'] as String,
    title: raw['title'] is String ? raw['title'] as String : '',
    alttitle: alttitleRaw is String ? alttitleRaw : null,
    released: releasedRaw is String ? releasedRaw : null,
    rating: ratingRaw is num ? ratingRaw.toDouble() : null,
    votecount: votecountRaw is int ? votecountRaw : 0,
    imageUrl: imageUrl,
    imageSexual: imageSexual,
    description: raw['description'] is String ? raw['description'] as String : '',
    developers: developers,
    tags: [for (final tag in scored.take(10)) tag.$1],
  );
}

class VndbClient {
  final http.Client _client;
  final String baseUrl;
  final Duration retryDelay;

  VndbClient(
      {http.Client? client,
      this.baseUrl = vndbApi,
      this.retryDelay = const Duration(seconds: 5)})
      : _client = client ?? http.Client();

  Future<http.Response> _post(Map<String, Object?> body) async {
    final uri = Uri.parse('$baseUrl/vn');
    Future<http.Response> send() => _client.post(uri, headers: {
          'Content-Type': 'application/json',
          'User-Agent': 'vn-launcher/$vnlVersion',
        }, body: jsonEncode(body));
    http.Response response;
    try {
      response = await send();
    } catch (e) {
      throw VndbException('request failed: $e');
    }
    if (response.statusCode == 429) {
      await Future<void>.delayed(retryDelay);
      try {
        response = await send();
      } catch (e) {
        throw VndbException('request failed: $e');
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw VndbException('HTTP ${response.statusCode}');
    }
    return response;
  }

  Future<List<VnSearchResult>> search(String query) async {
    final trimmed = query.trim();
    final id = vndbIdFromQuery(trimmed);
    final response = await _post({
      'filters': id == null ? ['search', '=', trimmed] : ['id', '=', id],
      'fields': _searchFields,
      'sort': 'searchrank',
      'results': 20,
    });
    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (e) {
      throw VndbException('invalid JSON: $e');
    }
    if (decoded is! Map || decoded['results'] is! List) {
      throw const VndbException('unexpected VNDB response shape');
    }
    final raws = <Map>[];
    for (final item in decoded['results'] as List) {
      if (item is Map && item['id'] is String) raws.add(item);
    }
    final folded = _foldTitle(trimmed);
    final exact = <Map>[];
    final rest = <Map>[];
    for (final raw in raws) {
      if (id == null && _titleMatches(raw, folded)) {
        exact.add(raw);
      } else {
        rest.add(raw);
      }
    }
    return [for (final raw in [...exact, ...rest]) _parseSearchResult(raw)];
  }

  /// VNDB `image.url` for one id, or null when the game has no image.
  Future<String?> fetchCoverUrl(String vndbId) async {
    final uri = Uri.parse('$baseUrl/vn');
    final http.Response response;
    try {
      response = await _client.post(uri, headers: {
        'Content-Type': 'application/json',
        'User-Agent': 'vn-launcher/$vnlVersion',
      }, body: jsonEncode({
        'filters': ['id', '=', vndbId],
        'fields': 'id,image.url',
        'results': 1,
      }));
    } catch (e) {
      throw VndbException('request failed: $e');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw VndbException('HTTP ${response.statusCode}');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (e) {
      throw VndbException('invalid JSON: $e');
    }
    if (decoded is! Map || decoded['results'] is! List) {
      throw const VndbException('unexpected VNDB response shape');
    }
    for (final raw in decoded['results'] as List) {
      if (raw is! Map) continue;
      final image = raw['image'];
      if (image is Map) {
        final url = image['url'];
        if (url is String && url.startsWith('http')) return url;
      }
      return null;
    }
    return null;
  }

  Future<List<VnRating>> fetchPage(Map<String, Object?> body) async {
    final response = await _post(body);
    return parseRatings(response.body);
  }
}

List<Map<String, Object?>> ratingRequestBodies(List<String> ids) {
  final bodies = <Map<String, Object?>>[];
  for (var i = 0; i < ids.length; i += 100) {
    final chunk = ids.sublist(i, min(i + 100, ids.length));
    final Object filters = chunk.length == 1
        ? ['id', '=', chunk.single]
        : ['or', for (final id in chunk) ['id', '=', id]];
    bodies.add({
      'filters': filters,
      'fields': 'id,rating,votecount,released',
      'results': 100,
    });
  }
  return bodies;
}

List<VnRating> parseRatings(String body) {
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } catch (e) {
    throw VndbException('invalid JSON: $e');
  }
  if (decoded is! Map || decoded['results'] is! List) {
    throw const VndbException('unexpected VNDB response shape');
  }
  final out = <VnRating>[];
  for (final raw in decoded['results'] as List) {
    if (raw is! Map || raw['id'] is! String) continue;
    final ratingRaw = raw['rating'];
    final votecountRaw = raw['votecount'];
    final releasedRaw = raw['released'];
    out.add(VnRating(
      id: raw['id'] as String,
      rating: ratingRaw is num ? ratingRaw.toDouble() : null,
      votecount: votecountRaw is int ? votecountRaw : 0,
      released: releasedRaw is String ? releasedRaw : null,
    ));
  }
  return out;
}

class RatingReport {
  final int updated;
  final List<String> notFound;
  final String? error;

  const RatingReport({this.updated = 0, List<String>? notFound, this.error})
      : notFound = notFound ?? const [];

  Map<String, Object?> toJson() =>
      {'updated': updated, 'not_found': notFound, 'error': error};
}

Future<RatingReport> refreshRatings(LoadedLibrary loaded, VndbClient client,
    {DateTime? now}) async {
  final fetchedAt = (now ?? DateTime.now()).toUtc();
  final seen = <String>{};
  final ids = <String>[];
  for (final game in loaded.library.games) {
    final vndbId = game.vndbId;
    if (vndbId == null || !seen.add(vndbId)) continue;
    ids.add(vndbId);
  }
  var updated = 0;
  final found = <String>{};
  for (final body in ratingRequestBodies(ids)) {
    final List<VnRating> ratings;
    try {
      ratings = await client.fetchPage(body);
    } catch (e) {
      // notFound is only meaningful for a complete fetch.
      return RatingReport(updated: updated, error: '$e');
    }
    final byId = {for (final r in ratings) r.id: r};
    found.addAll(byId.keys);
    for (final game in loaded.library.games) {
      final rating = byId[game.vndbId];
      if (rating == null) continue;
      game.vndbRating = rating.rating;
      game.vndbVotecount = rating.votecount;
      game.released = rating.released;
      game.vndbFetchedAt = fetchedAt;
      updated++;
    }
  }
  return RatingReport(
      updated: updated,
      notFound: [for (final id in ids) if (!found.contains(id)) id]);
}
