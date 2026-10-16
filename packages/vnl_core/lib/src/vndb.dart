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

class VndbClient {
  final http.Client _client;
  final String baseUrl;
  final Duration retryDelay;

  VndbClient(
      {http.Client? client,
      this.baseUrl = vndbApi,
      this.retryDelay = const Duration(seconds: 5)})
      : _client = client ?? http.Client();

  Future<List<VnRating>> fetchPage(Map<String, Object?> body) async {
    final uri = Uri.parse('$baseUrl/vn');
    Future<http.Response> post() => _client.post(uri, headers: {
          'Content-Type': 'application/json',
          'User-Agent': 'vn-launcher/$vnlVersion',
        }, body: jsonEncode(body));
    http.Response response;
    try {
      response = await post();
    } catch (e) {
      throw VndbException('request failed: $e');
    }
    if (response.statusCode == 429) {
      await Future<void>.delayed(retryDelay);
      try {
        response = await post();
      } catch (e) {
        throw VndbException('request failed: $e');
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw VndbException('HTTP ${response.statusCode}');
    }
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
