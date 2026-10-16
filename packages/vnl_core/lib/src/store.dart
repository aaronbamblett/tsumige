// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'json_read.dart';
import 'model.dart';
import 'paths.dart';

sealed class StoreException implements Exception {
  const StoreException();
}

class InvalidJson extends StoreException {
  final String path;
  final String message;

  const InvalidJson(this.path, this.message);

  @override
  String toString() => 'Invalid JSON in $path: $message';
}

class NewerSchema extends StoreException {
  final int found;
  final int supported;

  const NewerSchema(this.found, this.supported);

  @override
  String toString() =>
      'Unsupported schema version $found (supports $supported)';
}

class SkippedEntriesPresent extends StoreException {
  final int count;

  const SkippedEntriesPresent(this.count);

  @override
  String toString() => 'Refusing to save with $count skipped entries';
}

class ChangedOnDisk extends StoreException {
  final String path;

  const ChangedOnDisk(this.path);

  @override
  String toString() => 'Library changed on disk: $path';
}

String _backupName(DateTime u) {
  String two(int n) => n.toString().padLeft(2, '0');
  String three(int n) => n.toString().padLeft(3, '0');
  return 'library-${u.year}${two(u.month)}${two(u.day)}'
      'T${two(u.hour)}${two(u.minute)}${two(u.second)}.${three(u.millisecond)}Z.json';
}

Future<FileStamp> _stamp(File file) async {
  final stat = await file.stat();
  return FileStamp(length: stat.size, modified: stat.modified);
}

Future<LoadedLibrary> loadLibrary(DataDir dir) async {
  final file = dir.libraryJson;
  if (!await file.exists()) {
    return LoadedLibrary(library: Library(games: []));
  }
  final bytes = await file.readAsBytes();
  Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes));
  } catch (e) {
    throw InvalidJson(file.path, '$e');
  }
  if (decoded is! Map) {
    throw InvalidJson(file.path, 'top-level JSON must be an object');
  }
  final rawVersion = decoded['schema_version'];
  final found = rawVersion is int ? rawVersion : schemaVersion;
  if (found > schemaVersion) throw NewerSchema(found, schemaVersion);
  final rawGames = decoded['games'];
  final list = rawGames is List ? rawGames : const [];
  final games = <Game>[];
  final skipped = <SkippedEntry>[];
  for (var i = 0; i < list.length; i++) {
    final raw = list[i];
    try {
      if (raw is! Map) throw const FormatException('game must be an object');
      final id = readString(raw, 'id');
      if (!Uuid.isValidUUID(fromString: id)) {
        skipped.add(SkippedEntry(
            index: i,
            title: readStringOrNull(raw, 'title'),
            reason: 'missing or invalid id'));
        continue;
      }
      games.add(Game.fromJson(raw));
    } catch (e) {
      skipped.add(SkippedEntry(
          index: i,
          title: raw is Map ? readStringOrNull(raw, 'title') : null,
          reason: '$e'));
    }
  }
  return LoadedLibrary(
      library: Library(schemaVersion: found, games: games),
      skipped: skipped,
      stamp: await _stamp(file));
}

Future<void> saveLibrary(DataDir dir, LoadedLibrary loaded) async {
  if (loaded.skipped.isNotEmpty) {
    throw SkippedEntriesPresent(loaded.skipped.length);
  }
  final file = dir.libraryJson;
  final stamp = loaded.stamp;
  if (stamp == null) {
    if (await file.exists()) throw ChangedOnDisk(file.path);
  } else {
    if (!await file.exists()) throw ChangedOnDisk(file.path);
    if (await _stamp(file) != stamp) throw ChangedOnDisk(file.path);
  }
  if (await file.exists()) {
    await dir.backups.create(recursive: true);
    final base = _backupName(DateTime.now().toUtc());
    var name = base;
    var n = 2;
    while (await File(p.join(dir.backups.path, name)).exists()) {
      name = base.replaceFirst('.json', '-$n.json');
      n++;
    }
    await File(p.join(dir.backups.path, name))
        .writeAsBytes(await file.readAsBytes());
  } else {
    await file.parent.create(recursive: true);
  }
  final payload = jsonEncode({
    'schema_version': schemaVersion,
    'games': [for (final g in loaded.library.games) g.toJson()],
  });
  final tmp = File('${file.path}.$pid.tmp');
  await tmp.writeAsString(payload, flush: true);
  await tmp.rename(file.path);
  loaded.stamp = await _stamp(file);
}

Future<CoreSettings> loadCoreSettings(DataDir dir) async {
  final file = dir.settingsJson;
  if (!await file.exists()) return CoreSettings();
  final decoded = jsonDecode(await file.readAsString());
  if (decoded is! Map) return CoreSettings();
  return CoreSettings.fromJson(decoded);
}

Future<void> saveCoreSettings(DataDir dir, CoreSettings settings) async {
  final file = dir.settingsJson;
  await file.parent.create(recursive: true);
  final tmp = File('${file.path}.$pid.tmp');
  await tmp.writeAsString(jsonEncode(settings.toJson()), flush: true);
  await tmp.rename(file.path);
}
