// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tsumige/src/core/launch/session_recorder.dart';
import 'package:tsumige/src/core/model.dart';
import 'package:tsumige/src/core/paths.dart';
import 'package:tsumige/src/core/store.dart';

/// Reloads return fresh copies (as from disk) so a retry cannot append the
/// same session twice to one object.
class FakeStore implements SessionStore {
  FakeStore(this.current);

  LoadedLibrary current;
  var saves = 0;
  var failSaves = 0;

  @override
  Future<LoadedLibrary> load() async {
    final games = [
      for (final game in current.library.games) Game.fromJson(game.toJson()),
    ];
    return LoadedLibrary(
        library: Library(games: games), stamp: current.stamp);
  }

  @override
  Future<void> save(LoadedLibrary loaded) async {
    saves++;
    if (failSaves > 0) {
      failSaves--;
      throw const ChangedOnDisk('library.json');
    }
    current = loaded;
  }
}

void main() {
  late Directory temp;
  setUp(() {
    temp = Directory.systemTemp.createTempSync('tsumige_session_test_');
  });
  tearDown(() {
    temp.deleteSync(recursive: true);
  });

  test('recordSession appends one session and saves', () async {
    final store = FakeStore(LoadedLibrary(
        library: Library(games: [Game(id: 'g1', title: 'Alpha')])));
    final at = DateTime.utc(2026, 10, 17, 12);
    await recordSession(store, 'g1', at, 90);
    expect(store.saves, 1);
    final sessions = store.current.library.games.single.playSessions;
    expect(sessions, hasLength(1));
    expect(sessions.single.startedAt, at);
    expect(sessions.single.durationSeconds, 90);
  });

  test('recordSession reloads and retries once on ChangedOnDisk', () async {
    final store = FakeStore(LoadedLibrary(library: Library(games: [
      Game(id: 'g1', title: 'Alpha'),
      Game(id: 'ext', title: 'Changed elsewhere'),
    ])));
    store.failSaves = 1;
    final at = DateTime.utc(2026, 10, 17, 12);
    await recordSession(store, 'g1', at, 90);
    expect(store.saves, 2);
    final games = store.current.library.games;
    expect(games.map((g) => g.id), containsAll(['g1', 'ext']));
    expect(
        games.firstWhere((g) => g.id == 'g1').playSessions, hasLength(1));
  });

  test('a missing game drops the session without saving', () async {
    final store = FakeStore(LoadedLibrary(library: Library(games: [])));
    final messages = <String>[];
    await recordSession(store, 'gone', DateTime.utc(2026, 10, 17, 12), 90,
        log: messages.add);
    expect(store.saves, 0);
    expect(messages, hasLength(1));
    expect(messages.single, contains('gone'));
  });

  test('recovery turns a marker into a session and deletes it', () async {
    final dir = DataDir(temp.path);
    final store = FakeStore(LoadedLibrary(
        library: Library(games: [Game(id: 'g1', title: 'Alpha')])));
    final started = DateTime.utc(2026, 10, 17, 12);
    await writeRunningMarker(dir, 'g1', started, started.add(
        const Duration(seconds: 300)));
    final count = await recoverSessions(dir, store);
    expect(count, 1);
    final sessions = store.current.library.games.single.playSessions;
    expect(sessions, hasLength(1));
    expect(sessions.single.startedAt, started);
    expect(sessions.single.durationSeconds, 300);
    expect(
        File(p.join(temp.path, 'running', 'g1.json')).existsSync(), isFalse);
  });

  test('recovery with no markers returns zero', () async {
    final store = FakeStore(LoadedLibrary(library: Library(games: [])));
    expect(await recoverSessions(DataDir(temp.path), store), 0);
  });

  test('recovery drops an unreadable marker and keeps the count', () async {
    final dir = DataDir(temp.path);
    final store = FakeStore(LoadedLibrary(
        library: Library(games: [Game(id: 'g1', title: 'Alpha')])));
    final folder = Directory(p.join(temp.path, 'running'))
      ..createSync(recursive: true);
    File(p.join(folder.path, 'bad.json')).writeAsStringSync('not json');
    final messages = <String>[];
    expect(await recoverSessions(dir, store, log: messages.add), 0);
    expect(messages.single, contains('bad'));
    expect(
        File(p.join(folder.path, 'bad.json')).existsSync(), isFalse);
  });

  test('recovery drops a marker whose game was never seen', () async {
    final dir = DataDir(temp.path);
    final store = FakeStore(LoadedLibrary(
        library: Library(games: [Game(id: 'g1', title: 'Alpha')])));
    final started = DateTime.utc(2026, 10, 17, 12);
    await writeRunningMarker(dir, 'g1', started,
        started.add(const Duration(seconds: 300)),
        seen: false);
    expect(await recoverSessions(dir, store), 0);
    expect(store.current.library.games.single.playSessions, isEmpty);
    expect(
        File(p.join(temp.path, 'running', 'g1.json')).existsSync(), isFalse);
  });

  test('recovery still recovers a marker without the seen key', () async {
    final dir = DataDir(temp.path);
    final store = FakeStore(LoadedLibrary(
        library: Library(games: [Game(id: 'g1', title: 'Alpha')])));
    final started = DateTime.utc(2026, 10, 17, 12);
    final folder = Directory(p.join(temp.path, 'running'))
      ..createSync(recursive: true);
    File(p.join(folder.path, 'g1.json')).writeAsStringSync(jsonEncode({
      'started_at': started.toIso8601String(),
      'last_seen':
          started.add(const Duration(seconds: 300)).toIso8601String(),
    }));
    expect(await recoverSessions(dir, store), 1);
    final sessions = store.current.library.games.single.playSessions;
    expect(sessions, hasLength(1));
    expect(sessions.single.startedAt, started);
    expect(sessions.single.durationSeconds, 300);
    expect(File(p.join(folder.path, 'g1.json')).existsSync(), isFalse);
  });

  test('marker round-trips started_at and last_seen', () async {
    final dir = DataDir(temp.path);
    final started = DateTime.utc(2026, 10, 17, 12);
    final seen = started.add(const Duration(seconds: 60));
    await writeRunningMarker(dir, 'g1', started, seen);
    final data = jsonDecode(
        await File(p.join(temp.path, 'running', 'g1.json')).readAsString());
    expect(DateTime.parse(data['started_at'] as String), started);
    expect(DateTime.parse(data['last_seen'] as String), seen);
    expect(data['seen'], isTrue);
    await deleteRunningMarker(dir, 'g1');
    expect(
        File(p.join(temp.path, 'running', 'g1.json')).existsSync(), isFalse);
  });
}
