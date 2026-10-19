// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'json_read.dart';
import 'model.dart';
import 'version.dart';

const String vndbApi = 'https://api.vndb.org/kana';

class VndbException implements Exception {
  final String message;

  /// The HTTP status when the failure is one, so callers can spot a 429.
  final int? statusCode;

  const VndbException(this.message, {this.statusCode});

  @override
  String toString() => 'VndbException: $message';
}

class VnData {
  final String id;
  final String? title;
  final String? alttitle;
  final double? rating;
  final int votecount;
  final String? released;
  final int? lengthMinutes;
  final int? lengthVotes;
  final String? olang;
  final List<Developer> developers;
  final List<VndbTag> tags;
  final List<VnRelation> relations;

  const VnData({
    required this.id,
    this.title,
    this.alttitle,
    this.rating,
    this.votecount = 0,
    this.released,
    this.lengthMinutes,
    this.lengthVotes,
    this.olang,
    this.developers = const [],
    this.tags = const [],
    this.relations = const [],
  });
}

const String _vnDataFields =
    'id,title,alttitle,rating,votecount,released,length_minutes,length_votes,'
    'olang,developers{id,name,original},tags{name,rating,spoiler,category},'
    'relations{id,relation,relation_official,title,image.url}';

const String _artVnFields =
    'image.url,image.thumbnail,image.dims,'
    'screenshots.url,screenshots.thumbnail,screenshots.dims';

const String _artReleaseFields =
    'images.type,images.url,images.thumbnail,images.dims';

/// One VNDB image offered as cover or background. [width] and [height] are 0
/// when VNDB gives no dimensions.
class ArtCandidate {
  final String url;
  final String thumbnail;
  final int width;
  final int height;
  final String type;

  const ArtCandidate({
    required this.url,
    required this.thumbnail,
    required this.width,
    required this.height,
    required this.type,
  });

  bool get portrait => height >= width;
}

class ArtCandidates {
  final ArtCandidate? main;
  final List<ArtCandidate> releaseImages;
  final List<ArtCandidate> screenshots;

  const ArtCandidates({
    this.main,
    this.releaseImages = const [],
    this.screenshots = const [],
  });
}

ArtCandidate? _parseArt(Object? raw, String type) {
  if (raw is! Map) return null;
  final url = raw['url'];
  if (url is! String || !url.startsWith('http')) return null;
  final thumb = raw['thumbnail'];
  final dims = raw['dims'];
  final hasDims = dims is List && dims.length == 2 && dims.every((d) => d is int);
  return ArtCandidate(
    url: url,
    thumbnail: thumb is String && thumb.startsWith('http') ? thumb : url,
    width: hasDims ? dims[0] as int : 0,
    height: hasDims ? dims[1] as int : 0,
    type: type,
  );
}

class VnSearchResult {
  final String id;
  final String title;
  final String? alttitle;
  final List<String> titles;
  final List<String> aliases;
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
    List<String>? titles,
    List<String>? aliases,
    this.released,
    this.rating,
    this.votecount = 0,
    this.imageUrl,
    this.imageSexual = 0,
    this.description = '',
    List<String>? developers,
    List<String>? tags,
  })  : titles = titles ?? const [],
        aliases = aliases ?? const [],
        developers = developers ?? const [],
        tags = tags ?? const [];
}

const String _searchFields =
    'id,title,alttitle,titles.title,aliases,released,rating,votecount,'
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
  final titlesRaw = raw['titles'];
  final titles = <String>[
    if (titlesRaw is List)
      for (final entry in titlesRaw)
        if (entry is Map && entry['title'] is String) entry['title'] as String,
  ];
  final aliasesRaw = raw['aliases'];
  final aliases = <String>[
    if (aliasesRaw is List)
      for (final alias in aliasesRaw)
        if (alias is String) alias,
  ];
  return VnSearchResult(
    id: raw['id'] as String,
    title: raw['title'] is String ? raw['title'] as String : '',
    alttitle: alttitleRaw is String ? alttitleRaw : null,
    titles: titles,
    aliases: aliases,
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

/// A Steam app linked to a VN, labelled with the title of the release that links it.
typedef SteamApp = ({int appId, String title});

class VndbClient {
  final http.Client _client;
  final String baseUrl;
  final Duration retryDelay;

  VndbClient(
      {http.Client? client,
      this.baseUrl = vndbApi,
      this.retryDelay = const Duration(seconds: 5)})
      : _client = client ?? http.Client();

  Future<http.Response> _post(String path, Map<String, Object?> body) async {
    final uri = Uri.parse('$baseUrl$path');
    Future<http.Response> send() => _client.post(uri, headers: {
          'Content-Type': 'application/json',
          'User-Agent': 'tsumige/$appVersion',
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
      throw VndbException(
        'HTTP ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
    return response;
  }

  Future<List<VnSearchResult>> search(String query) async {
    final trimmed = query.trim();
    final id = vndbIdFromQuery(trimmed);
    final response = await _post('/vn', {
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
        'User-Agent': 'tsumige/$appVersion',
      }, body: jsonEncode({
        'filters': ['id', '=', vndbId],
        'fields': 'id,image.url',
        'results': 1,
      }));
    } catch (e) {
      throw VndbException('request failed: $e');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw VndbException(
        'HTTP ${response.statusCode}',
        statusCode: response.statusCode,
      );
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

  Future<({List<Map> results, bool more})> _postPage(
      String path, Map<String, Object?> body) async {
    final response = await _post(path, body);
    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (e) {
      throw VndbException('invalid JSON: $e');
    }
    if (decoded is! Map || decoded['results'] is! List) {
      throw const VndbException('unexpected VNDB response shape');
    }
    return (
      results: [
        for (final raw in decoded['results'] as List)
          if (raw is Map) raw
      ],
      more: decoded['more'] == true,
    );
  }

  Future<List<VnData>> fetchVnData(List<String> ids) async {
    final out = <VnData>[];
    for (var i = 0; i < ids.length; i += 100) {
      final chunk = ids.sublist(i, min(i + 100, ids.length));
      for (var page = 1;; page++) {
        final result = await _postPage('/vn', {
          'filters': _idFilter(chunk),
          'fields': _vnDataFields,
          'results': 100,
          'page': page,
        });
        for (final raw in result.results) {
          final vn = _parseVnData(raw);
          if (vn != null) out.add(vn);
        }
        if (!result.more) break;
      }
    }
    return out;
  }

  /// The VN's main image, its screenshots, and the images of its releases
  /// (deduplicated by url, with the main image left out of the release list).
  Future<ArtCandidates> fetchArtCandidates(String vndbId) async {
    final vnRows = await _postPage('/vn', {
      'filters': ['id', '=', vndbId],
      'fields': _artVnFields,
      'results': 1,
    });
    final vn = vnRows.results.isEmpty ? null : vnRows.results.first;
    final main = vn == null ? null : _parseArt(vn['image'], 'main');
    final shots = vn?['screenshots'];
    final screenshots = [
      for (final shot in shots is List ? shots : const [])
        ?_parseArt(shot, 'screenshot'),
    ];
    final seen = {if (main != null) main.url};
    final releaseImages = <ArtCandidate>[];
    for (var page = 1;; page++) {
      final result = await _postPage('/release', {
        'filters': ['vn', '=', ['id', '=', vndbId]],
        'fields': _artReleaseFields,
        'results': 100,
        'page': page,
      });
      for (final release in result.results) {
        final images = release['images'];
        if (images is! List) continue;
        for (final image in images) {
          if (image is! Map) continue;
          final type = image['type'];
          final art = _parseArt(image, type is String ? type : 'release');
          if (art == null || !seen.add(art.url)) continue;
          releaseImages.add(art);
        }
      }
      if (!result.more) break;
    }
    return ArtCandidates(
      main: main,
      releaseImages: releaseImages,
      screenshots: screenshots,
    );
  }

  /// Steam apps linked to [vndbId] through its releases' extlinks, deduplicated
  /// by app id in first-seen order, each with the title of the first release
  /// that linked it.
  Future<List<SteamApp>> fetchSteamApps(String vndbId) async {
    final out = <SteamApp>[];
    final seen = <int>{};
    for (var page = 1;; page++) {
      final result = await _postPage('/release', {
        'filters': [
          'and',
          ['vn', '=', ['id', '=', vndbId]],
          ['extlink', '=', 'steam'],
        ],
        'fields': 'title,extlinks.name,extlinks.id',
        'results': 100,
        'page': page,
      });
      for (final release in result.results) {
        final title = release['title'];
        final extlinks = release['extlinks'];
        if (extlinks is! List) continue;
        for (final link in extlinks) {
          if (link is! Map || link['name'] != 'steam') continue;
          final raw = link['id'];
          final appId = raw is int
              ? raw
              : raw is String
              ? int.tryParse(raw)
              : null;
          if (appId != null && seen.add(appId)) {
            out.add((appId: appId, title: title is String ? title : ''));
          }
        }
      }
      if (!result.more) break;
    }
    return out;
  }

  /// VN ids, among [ids], that have at least one release with `has_ero`.
  Future<Set<String>> fetchAdultVnIds(List<String> ids) async {
    final out = <String>{};
    for (var i = 0; i < ids.length; i += 100) {
      final chunk = ids.sublist(i, min(i + 100, ids.length));
      final chunkSet = chunk.toSet();
      for (var page = 1;; page++) {
        final result = await _postPage('/release', {
          'filters': [
            'and',
            ['has_ero', '=', 1],
            ['vn', '=', _idFilter(chunk)],
          ],
          'fields': 'vns.id',
          'results': 100,
          'page': page,
        });
        for (final raw in result.results) {
          final vns = raw['vns'];
          if (vns is! List) continue;
          for (final vn in vns) {
            final id = vn is Map ? vn['id'] : null;
            if (id is String && chunkSet.contains(id)) out.add(id);
          }
        }
        if (!result.more) break;
      }
    }
    return out;
  }
}

Object _idFilter(List<String> ids) => ids.length == 1
    ? ['id', '=', ids.single]
    : ['or', for (final id in ids) ['id', '=', id]];

VnData? _parseVnData(Map raw) {
  final id = raw['id'];
  if (id is! String) return null;
  return VnData(
    id: id,
    title: readStringOrNull(raw, 'title'),
    alttitle: readStringOrNull(raw, 'alttitle'),
    rating: readDoubleOrNull(raw, 'rating'),
    votecount: readIntOrNull(raw, 'votecount') ?? 0,
    released: readStringOrNull(raw, 'released'),
    lengthMinutes: readIntOrNull(raw, 'length_minutes'),
    lengthVotes: readIntOrNull(raw, 'length_votes'),
    olang: readStringOrNull(raw, 'olang'),
    developers: readList(raw, 'developers', Developer.fromJson),
    tags: [
      for (final tag in readList(raw, 'tags', VndbTag.fromJson))
        if (tag.rating > 0) tag
    ],
    relations: readList(raw, 'relations', _parseRelation),
  );
}

VnRelation? _parseRelation(Object? raw) {
  if (raw is! Map || raw['id'] is! String) return null;
  final image = raw['image'];
  final url = image is Map ? readStringOrNull(image, 'url') : null;
  return VnRelation(
    vndbId: raw['id'] as String,
    relation: readString(raw, 'relation'),
    title: readString(raw, 'title'),
    imageUrl: url != null && url.startsWith('http') ? url : null,
    official: raw['relation_official'] == true,
  );
}

class VndbRefreshReport {
  final int updated;
  final List<String> notFound;
  final String? error;

  const VndbRefreshReport(
      {this.updated = 0, List<String>? notFound, this.error})
      : notFound = notFound ?? const [];

  Map<String, Object?> toJson() =>
      {'updated': updated, 'not_found': notFound, 'error': error};
}

void applyVnData(Game game, VnData vn,
    {required bool adult, required DateTime fetchedAt}) {
  game.vndbRating = vn.rating;
  game.vndbVotecount = vn.votecount;
  game.released = vn.released;
  game.vndbOriginalTitle = vn.alttitle;
  game.developers = [...vn.developers];
  game.lengthMinutes = vn.lengthMinutes;
  game.lengthVotes = vn.lengthVotes;
  game.originalLanguage = vn.olang;
  game.vndbTags = [...vn.tags];
  game.relations = [...vn.relations];
  game.adultVndb = adult;
  game.vndbFetchedAt = fetchedAt;
  game.vndbDataFetchedAt = fetchedAt;
}

/// Fills every VNDB field for the library's games, 100 ids per chunk. A gap
/// of [gap] separates requests, so a full library does not burst VNDB.
Future<VndbRefreshReport> refreshVndbData(LoadedLibrary loaded, VndbClient client,
    {DateTime? now, Duration gap = const Duration(seconds: 1)}) async {
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
  var sent = 0;
  Future<void> pace() async {
    if (sent++ > 0) await Future<void>.delayed(gap);
  }

  for (var i = 0; i < ids.length; i += 100) {
    final chunk = ids.sublist(i, min(i + 100, ids.length));
    final List<VnData> vns;
    final Set<String> adult;
    try {
      await pace();
      vns = await client.fetchVnData(chunk);
      await pace();
      adult = await client.fetchAdultVnIds(chunk);
    } catch (e) {
      // notFound is only meaningful for a complete fetch.
      return VndbRefreshReport(updated: updated, error: '$e');
    }
    final byId = {for (final vn in vns) vn.id: vn};
    found.addAll(byId.keys);
    for (final game in loaded.library.games) {
      final vn = byId[game.vndbId];
      if (vn == null) continue;
      applyVnData(game, vn, adult: adult.contains(vn.id), fetchedAt: fetchedAt);
      updated++;
    }
  }
  return VndbRefreshReport(
      updated: updated,
      notFound: [for (final id in ids) if (!found.contains(id)) id]);
}
