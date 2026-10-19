// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/widgets.dart';

import 'json_read.dart';

const int schemaVersion = 1;

const String vndbTitleKey = 'title';
const String vndbOriginalTitleKey = 'original_title';
const String vndbDevelopersKey = 'developers';
const String vndbReleasedKey = 'released';

enum Language { japanese, english }

enum LaunchMode { proton, wine, native, steam }

Language? parseLanguage(String? s) => switch (s) {
      'japanese' => Language.japanese,
      'english' => Language.english,
      _ => null,
    };

LaunchMode? parseLaunchMode(String? s) => switch (s) {
      'proton' => LaunchMode.proton,
      'wine' => LaunchMode.wine,
      'native' => LaunchMode.native,
      'steam' => LaunchMode.steam,
      _ => null,
    };

class Library {
  int schemaVersion;
  List<Game> games;

  Library({this.schemaVersion = 1, List<Game>? games})
      : games = games ?? [];
}

class Game {
  String id;
  String title;
  String description;
  String notes;
  List<String> tags;
  bool favourite;
  bool needsReview;
  DateTime addedAt;
  String? vndbId;
  String? released;
  double? vndbRating;
  int? vndbVotecount;
  DateTime? vndbFetchedAt;
  Language? language;
  String? cover;
  String? background;
  String? coverSource;
  String? backgroundSource;
  Alignment? coverAlignment;
  Alignment? backgroundAlignment;
  LaunchOverrides launch;
  List<PlaySession> playSessions;
  String? vndbOriginalTitle;
  List<Developer> developers;
  int? lengthMinutes;
  int? lengthVotes;
  String? originalLanguage;
  List<VndbTag> vndbTags;
  List<VnRelation> relations;
  bool? adultVndb;
  bool? adultOverride;
  DateTime? vndbDataFetchedAt;
  Map<String, Object?> vndbOriginals;

  Game({
    required this.id,
    this.title = '',
    this.description = '',
    this.notes = '',
    List<String>? tags,
    this.favourite = false,
    this.needsReview = false,
    DateTime? addedAt,
    this.vndbId,
    this.released,
    this.vndbRating,
    this.vndbVotecount,
    this.vndbFetchedAt,
    this.language,
    this.cover,
    this.background,
    this.coverSource,
    this.backgroundSource,
    this.coverAlignment,
    this.backgroundAlignment,
    LaunchOverrides? launch,
    List<PlaySession>? playSessions,
    this.vndbOriginalTitle,
    List<Developer>? developers,
    this.lengthMinutes,
    this.lengthVotes,
    this.originalLanguage,
    List<VndbTag>? vndbTags,
    List<VnRelation>? relations,
    this.adultVndb,
    this.adultOverride,
    this.vndbDataFetchedAt,
    Map<String, Object?>? vndbOriginals,
  })  : vndbOriginals = vndbOriginals ?? {},
        tags = tags ?? [],
        addedAt = addedAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        launch = launch ?? LaunchOverrides(),
        playSessions = playSessions ?? [],
        developers = developers ?? [],
        vndbTags = vndbTags ?? [],
        relations = relations ?? [];

  factory Game.fromJson(Map m) => Game(
        id: readString(m, 'id'),
        title: readString(m, 'title'),
        description: readString(m, 'description'),
        notes: readString(m, 'notes'),
        tags: readStringList(m, 'tags'),
        favourite: readBool(m, 'favourite'),
        needsReview: readBool(m, 'needs_review'),
        addedAt: readDateOrNull(m, 'added_at'),
        vndbId: readStringOrNull(m, 'vndb_id'),
        released: readStringOrNull(m, 'released'),
        vndbRating: readDoubleOrNull(m, 'vndb_rating'),
        vndbVotecount: readIntOrNull(m, 'vndb_votecount'),
        vndbFetchedAt: readDateOrNull(m, 'vndb_fetched_at'),
        language: parseLanguage(readStringOrNull(m, 'language')),
        cover: readStringOrNull(m, 'cover'),
        background: readStringOrNull(m, 'background'),
        coverSource: readStringOrNull(m, 'cover_source'),
        backgroundSource: readStringOrNull(m, 'background_source'),
        coverAlignment: readAlignmentOrNull(m, 'cover_alignment'),
        backgroundAlignment: readAlignmentOrNull(m, 'background_alignment'),
        launch: m['launch'] is Map
            ? LaunchOverrides.fromJson(m['launch'] as Map)
            : LaunchOverrides(),
        playSessions:
            readList(m, 'play_sessions', (e) => PlaySession.fromJson(e)),
        vndbOriginalTitle: readStringOrNull(m, 'original_title'),
        developers: readList(m, 'developers', (e) => Developer.fromJson(e)),
        lengthMinutes: readIntOrNull(m, 'length_minutes'),
        lengthVotes: readIntOrNull(m, 'length_votes'),
        originalLanguage: readStringOrNull(m, 'original_language'),
        vndbTags: readList(m, 'vndb_tags', (e) => VndbTag.fromJson(e)),
        relations: readList(m, 'relations', (e) => VnRelation.fromJson(e)),
        adultVndb: _boolOrNull(m, 'adult_vndb'),
        adultOverride: _boolOrNull(m, 'adult_override'),
        vndbDataFetchedAt: readDateOrNull(m, 'vndb_data_fetched_at'),
        vndbOriginals: readVndbOriginals(m['vndb_originals']),
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'notes': notes,
        'tags': tags,
        'favourite': favourite,
        'needs_review': needsReview,
        'added_at': addedAt.toUtc().toIso8601String(),
        'vndb_id': vndbId,
        'released': released,
        'vndb_rating': vndbRating,
        'vndb_votecount': vndbVotecount,
        'vndb_fetched_at': vndbFetchedAt?.toUtc().toIso8601String(),
        'language': language?.name,
        'cover': cover,
        'background': background,
        'cover_source': coverSource,
        'background_source': backgroundSource,
        if (coverAlignment != null)
          'cover_alignment': [coverAlignment!.x, coverAlignment!.y],
        if (backgroundAlignment != null)
          'background_alignment': [
            backgroundAlignment!.x,
            backgroundAlignment!.y,
          ],
        'launch': launch.toJson(),
        'play_sessions': [for (final s in playSessions) s.toJson()],
        'original_title': vndbOriginalTitle,
        'developers': [for (final d in developers) d.toJson()],
        'length_minutes': lengthMinutes,
        'length_votes': lengthVotes,
        'original_language': originalLanguage,
        'vndb_tags': [for (final t in vndbTags) t.toJson()],
        'relations': [for (final r in relations) r.toJson()],
        'adult_vndb': adultVndb,
        'adult_override': adultOverride,
        'vndb_data_fetched_at': vndbDataFetchedAt?.toUtc().toIso8601String(),
        if (vndbOriginals.isNotEmpty) 'vndb_originals': vndbOriginals,
      };

  bool get isAdult => adultOverride ?? adultVndb ?? false;

  List<Developer> get vndbOriginalDevelopers {
    final raw = vndbOriginals[vndbDevelopersKey];
    if (raw is! List) return const [];
    return [for (final entry in raw) Developer.fromJson(entry)];
  }

  int get totalPlaytimeSeconds =>
      playSessions.fold(0, (sum, s) => sum + s.durationSeconds);

  DateTime? get lastPlayedAt {
    DateTime? latest;
    for (final s in playSessions) {
      if (latest == null || s.startedAt.isAfter(latest)) latest = s.startedAt;
    }
    return latest;
  }
}

bool? _boolOrNull(Map m, String k) {
  final v = m[k];
  return v is bool ? v : null;
}

/// Reads the VNDB values kept for fields the user edited. Kept in the same
/// JSON shape they are written in: strings and lists of developer maps.
Map<String, Object?> readVndbOriginals(Object? raw) {
  if (raw is! Map) return {};
  final out = <String, Object?>{};
  for (final key in const [
    vndbTitleKey,
    vndbOriginalTitleKey,
    vndbReleasedKey,
  ]) {
    if (!raw.containsKey(key)) continue;
    final value = raw[key];
    out[key] = value is String ? value : null;
  }
  if (raw.containsKey(vndbDevelopersKey)) {
    final value = raw[vndbDevelopersKey];
    out[vndbDevelopersKey] = [
      if (value is List)
        for (final entry in value)
          if (entry is Map && entry['id'] is String)
            Map<String, Object?>.from(entry),
    ];
  }
  return out;
}

/// Reads an [Alignment] from a two-number `[x, y]` list. Absent, null or
/// malformed values mean no saved position. Components are clamped to -1..1.
Alignment? readAlignmentOrNull(Map m, String k) {
  final v = m[k];
  if (v == null) return null;
  if (v is! List || v.length != 2) return null;
  double? component(Object? e) => switch (e) {
    double d => d,
    int i => i.toDouble(),
    _ => null,
  };
  final x = component(v[0]);
  final y = component(v[1]);
  if (x == null || y == null) return null;
  return Alignment(x.clamp(-1, 1), y.clamp(-1, 1));
}

class Developer {
  final String id;
  final String name;
  final String? original;

  const Developer({required this.id, this.name = '', this.original});

  factory Developer.fromJson(Object? raw) {
    if (raw is! Map || raw['id'] is! String) {
      throw const FormatException('developer needs an id');
    }
    return Developer(
      id: raw['id'] as String,
      name: readString(raw, 'name'),
      original: readStringOrNull(raw, 'original'),
    );
  }

  Map<String, Object?> toJson() =>
      {'id': id, 'name': name, 'original': original};
}

class VndbTag {
  final String name;
  final double rating;
  final int spoiler;
  final String category;

  const VndbTag({
    required this.name,
    required this.rating,
    required this.spoiler,
    required this.category,
  });

  factory VndbTag.fromJson(Object? raw) {
    if (raw is! Map || raw['name'] is! String) {
      throw const FormatException('tag needs a name');
    }
    return VndbTag(
      name: raw['name'] as String,
      rating: readDoubleOrNull(raw, 'rating') ?? 0,
      spoiler: readIntOrNull(raw, 'spoiler') ?? 0,
      category: readString(raw, 'category'),
    );
  }

  Map<String, Object?> toJson() => {
        'name': name,
        'rating': rating,
        'spoiler': spoiler,
        'category': category,
      };
}

class VnRelation {
  final String vndbId;
  final String relation;
  final String title;
  final String? imageUrl;
  final bool official;

  const VnRelation({
    required this.vndbId,
    required this.relation,
    required this.title,
    this.imageUrl,
    required this.official,
  });

  factory VnRelation.fromJson(Object? raw) {
    if (raw is! Map || raw['vndb_id'] is! String) {
      throw const FormatException('relation needs a vndb_id');
    }
    return VnRelation(
      vndbId: raw['vndb_id'] as String,
      relation: readString(raw, 'relation'),
      title: readString(raw, 'title'),
      imageUrl: readStringOrNull(raw, 'image_url'),
      official: _boolOrNull(raw, 'official') ?? false,
    );
  }

  Map<String, Object?> toJson() => {
        'vndb_id': vndbId,
        'relation': relation,
        'title': title,
        'image_url': imageUrl,
        'official': official,
      };
}

class LaunchOverrides {
  LaunchMode? mode;
  String? executable;
  String? runner;
  String? prefix;
  String? locale;
  String? umuGameId;
  String? arguments;
  String? environment;
  int? steamAppId;

  LaunchOverrides({
    this.mode,
    this.executable,
    this.runner,
    this.prefix,
    this.locale,
    this.umuGameId,
    this.arguments,
    this.environment,
    this.steamAppId,
  });

  factory LaunchOverrides.fromJson(Map m) => LaunchOverrides(
        mode: parseLaunchMode(readStringOrNull(m, 'mode')),
        executable: readStringOrNull(m, 'executable'),
        runner: readStringOrNull(m, 'runner'),
        prefix: readStringOrNull(m, 'prefix'),
        locale: readStringOrNull(m, 'locale'),
        umuGameId: readStringOrNull(m, 'umu_game_id'),
        arguments: readStringOrNull(m, 'arguments'),
        environment: readStringOrNull(m, 'environment'),
        steamAppId: readIntOrNull(m, 'steam_app_id'),
      );

  Map<String, Object?> toJson() => {
        'mode': mode?.name,
        'executable': executable,
        'runner': runner,
        'prefix': prefix,
        'locale': locale,
        'umu_game_id': umuGameId,
        'arguments': arguments,
        'environment': environment,
        'steam_app_id': steamAppId,
      };
}

class PlaySession {
  DateTime startedAt;
  int durationSeconds;
  String? notes;

  PlaySession(
      {required this.startedAt, this.durationSeconds = 0, this.notes});

  factory PlaySession.fromJson(Object? raw) {
    if (raw is! Map) throw const FormatException('session must be an object');
    final startedAt = readDateOrNull(raw, 'started_at');
    if (startedAt == null) {
      throw const FormatException('session needs a valid started_at');
    }
    return PlaySession(
      startedAt: startedAt,
      durationSeconds: readIntOrNull(raw, 'duration_seconds') ?? 0,
      notes: readStringOrNull(raw, 'notes'),
    );
  }

  Map<String, Object?> toJson() => {
        'started_at': startedAt.toUtc().toIso8601String(),
        'duration_seconds': durationSeconds,
        'notes': notes,
      };
}

class SkippedEntry {
  final int index;
  final String? title;
  final String reason;

  const SkippedEntry(
      {required this.index, this.title, required this.reason});
}

class FileStamp {
  final int length;
  final DateTime modified;

  const FileStamp({required this.length, required this.modified});

  @override
  bool operator ==(Object other) =>
      other is FileStamp &&
      other.length == length &&
      other.modified == modified;

  @override
  int get hashCode => Object.hash(length, modified);
}

class LoadedLibrary {
  final Library library;
  final List<SkippedEntry> skipped;
  FileStamp? stamp;

  LoadedLibrary({required this.library, List<SkippedEntry>? skipped, this.stamp})
      : skipped = skipped ?? [];
}
