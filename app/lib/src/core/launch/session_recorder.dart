// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../model.dart';
import '../paths.dart';
import '../store.dart';

/// The loader/saver a session write goes through. The app passes its
/// repository behind this interface so core stays widget-free and tests
/// can fake it.
abstract class SessionStore {
  Future<LoadedLibrary> load();
  Future<void> save(LoadedLibrary loaded);
}

Game? _findGame(Library library, String gameId) {
  for (final game in library.games) {
    if (game.id == gameId) return game;
  }
  return null;
}

void _report(void Function(String message)? log, String message) {
  if (log != null) {
    log(message);
  } else {
    stderr.writeln(message);
  }
}

/// Reloads the library fresh, appends the session to that game, and saves,
/// so a long play session never overwrites other changes made while the
/// game ran. Retries once after a [ChangedOnDisk]; a game that no longer
/// exists drops the session.
Future<void> recordSession(
  SessionStore store,
  String gameId,
  DateTime startedAt,
  int durationSeconds, {
  void Function(String message)? log,
}) async {
  var loaded = await store.load();
  var game = _findGame(loaded.library, gameId);
  if (game == null) {
    _report(log, 'vn-launcher: dropping play session for missing game $gameId');
    return;
  }
  game.playSessions.add(
    PlaySession(startedAt: startedAt, durationSeconds: durationSeconds),
  );
  try {
    await store.save(loaded);
  } on ChangedOnDisk {
    loaded = await store.load();
    game = _findGame(loaded.library, gameId);
    if (game == null) {
      _report(
          log, 'vn-launcher: dropping play session for missing game $gameId');
      return;
    }
    game.playSessions.add(
      PlaySession(startedAt: startedAt, durationSeconds: durationSeconds),
    );
    await store.save(loaded);
  }
}

Directory runningDir(DataDir dir) => Directory(p.join(dir.root, 'running'));

/// Writes `running/<gameId>.json` with `{started_at, last_seen}`.
Future<void> writeRunningMarker(
    DataDir dir, String gameId, DateTime startedAt, DateTime lastSeen) async {
  final folder = runningDir(dir);
  await folder.create(recursive: true);
  final payload = jsonEncode({
    'started_at': startedAt.toUtc().toIso8601String(),
    'last_seen': lastSeen.toUtc().toIso8601String(),
  });
  await File(p.join(folder.path, '$gameId.json')).writeAsString(payload);
}

Future<void> deleteRunningMarker(DataDir dir, String gameId) async {
  try {
    await File(p.join(runningDir(dir).path, '$gameId.json')).delete();
  } on PathNotFoundException {
    return;
  }
}

/// Turns every leftover running marker into a session lasting
/// `last_seen - started_at`, deletes the markers, and returns the count.
/// Markers that fail to save are kept for the next start.
Future<int> recoverSessions(
  DataDir dir,
  SessionStore store, {
  void Function(String message)? log,
}) async {
  final folder = runningDir(dir);
  if (!await folder.exists()) return 0;
  final markers = await folder
      .list()
      .where((entry) => entry is File && entry.path.endsWith('.json'))
      .toList();
  var count = 0;
  for (final marker in markers) {
    final file = marker as File;
    final gameId = p.basenameWithoutExtension(file.path);
    DateTime startedAt;
    DateTime lastSeen;
    try {
      final data = jsonDecode(await file.readAsString());
      if (data is! Map) throw const FormatException('marker is not an object');
      startedAt = DateTime.parse('${data['started_at']}');
      lastSeen = DateTime.parse('${data['last_seen']}');
    } catch (e) {
      _report(log, 'vn-launcher: ignoring unreadable running marker '
          'for $gameId: $e');
      try {
        await file.delete();
      } catch (_) {}
      continue;
    }
    var seconds = lastSeen.difference(startedAt).inSeconds;
    if (seconds < 0) seconds = 0;
    try {
      await recordSession(store, gameId, startedAt, seconds, log: log);
    } catch (e) {
      _report(log, 'vn-launcher: could not recover session for $gameId: $e');
      continue;
    }
    try {
      await file.delete();
    } catch (_) {}
    count++;
  }
  return count;
}
