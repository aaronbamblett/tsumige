// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:vnl/src/core/model.dart';
import 'package:vnl/src/core/paths.dart';
import 'package:vnl/src/core/store.dart';

Future<DataDir> freshDir() async {
  final tmp = await Directory.systemTemp.createTemp('vnl-store-');
  return DataDir(tmp.path);
}

Map<String, Object?> gameMap(String id, [String title = 'Game']) => {
      'id': id,
      'title': title,
    };

Game fullGame(String id) => Game(
      id: id,
      title: 'Subahibi',
      description: 'A story.',
      notes: 'vndb:v947549\nkept verbatim',
      tags: const ['mystery', 'denpa'],
      favourite: true,
      addedAt: DateTime.utc(2026, 10, 1, 12),
      vndbId: 'v947549',
      released: '2016-03-31',
      vndbRating: 84.23,
      vndbVotecount: 1337,
      vndbFetchedAt: DateTime.utc(2026, 10, 2, 8, 30),
      language: Language.japanese,
      cover: 'cover.png',
      launch: LaunchOverrides(
        mode: LaunchMode.proton,
        executable: '/games/suba/start.sh',
        runner: 'umu-proton',
        prefix: '/games/suba/prefix',
        locale: 'ja_JP.UTF-8',
        umuGameId: 'umu-default',
        arguments: '--fullscreen',
        environment: 'KEY=value',
        steamAppId: 12345,
      ),
      playSessions: [
        PlaySession(
            startedAt: DateTime.utc(2026, 10, 3, 14),
            durationSeconds: 600),
        PlaySession(
            startedAt: DateTime.utc(2026, 10, 4, 14),
            durationSeconds: 3000,
            notes: 's'),
      ],
    );

void main() {
  setUp(resetBackupSessionForTest);

  test('missing file loads empty', () async {
    final dir = await freshDir();
    final loaded = await loadLibrary(dir);
    expect(loaded.library.games, isEmpty);
    expect(loaded.skipped, isEmpty);
    expect(loaded.stamp, isNull);
  });

  test('round trip', () async {
    final dir = await freshDir();
    final id = const Uuid().v4();
    final game = fullGame(id);
    final loaded = LoadedLibrary(library: Library(games: [game]));
    await saveLibrary(dir, loaded);
    final again = await loadLibrary(dir);
    expect(again.library.games, hasLength(1));
    expect(again.library.games.single.toJson(), equals(game.toJson()));
  });

  test('null and missing fields default', () async {
    final dir = await freshDir();
    final id = const Uuid().v4();
    await dir.libraryJson.writeAsString(jsonEncode({
      'schema_version': 1,
      'games': [
        {
          'id': id,
          'title': null,
          'tags': null,
          'launch': null,
          'play_sessions': [
            null,
            {'started_at': 'bad'}
          ],
        }
      ],
    }));
    final loaded = await loadLibrary(dir);
    expect(loaded.skipped, isEmpty);
    final game = loaded.library.games.single;
    expect(game.title, isEmpty);
    expect(game.tags, isEmpty);
    expect(game.launch.mode, isNull);
    expect(game.playSessions, isEmpty);
  });

  test('legacy route keys load and are not written back', () async {
    final dir = await freshDir();
    final id = const Uuid().v4();
    await dir.libraryJson.writeAsString(jsonEncode({
      'schema_version': 1,
      'games': [
        {
          'id': id,
          'title': 'Legacy',
          'routes': [
            {'name': 'x', 'completed': true}
          ],
          'active_route': 'x',
        }
      ],
    }));
    final loaded = await loadLibrary(dir);
    expect(loaded.skipped, isEmpty);
    expect(loaded.library.games.single.title, 'Legacy');
    await saveLibrary(dir, loaded);
    final saved = jsonDecode(await dir.libraryJson.readAsString())
        as Map<String, Object?>;
    final game = (saved['games'] as List).single as Map<String, Object?>;
    expect(game.containsKey('routes'), isFalse);
    expect(game.containsKey('active_route'), isFalse);
  });

  test('bad entry skipped, others load', () async {
    final dir = await freshDir();
    final a = const Uuid().v4();
    final b = const Uuid().v4();
    await dir.libraryJson.writeAsString(jsonEncode({
      'schema_version': 1,
      'games': [gameMap(a, 'First'), {'id': 'not-a-uuid', 'title': 'Bad'}, gameMap(b, 'Third')],
    }));
    final loaded = await loadLibrary(dir);
    expect(loaded.library.games.map((g) => g.title), ['First', 'Third']);
    expect(loaded.skipped, hasLength(1));
    expect(loaded.skipped.single.index, 1);
    expect(loaded.skipped.single.title, 'Bad');
  });

  test('save refuses while skipping', () async {
    final dir = await freshDir();
    final a = const Uuid().v4();
    await dir.libraryJson.writeAsString(jsonEncode({
      'schema_version': 1,
      'games': [gameMap(a, 'Kept'), {'id': 'nope', 'title': 'Bad'}],
    }));
    final before = await dir.libraryJson.readAsBytes();
    final loaded = await loadLibrary(dir);
    expect(loaded.skipped, hasLength(1));
    await expectLater(
        saveLibrary(dir, loaded),
        throwsA(isA<SkippedEntriesPresent>()
            .having((e) => e.count, 'count', 1)));
    expect(await dir.libraryJson.readAsBytes(), equals(before));
  });

  test('corrupt file is an error and untouched', () async {
    final dir = await freshDir();
    await dir.libraryJson.writeAsString('{"schema_version":1,"games":[');
    final before = await dir.libraryJson.readAsBytes();
    await expectLater(loadLibrary(dir), throwsA(isA<InvalidJson>()));
    expect(await dir.libraryJson.readAsBytes(), equals(before));
  });

  test('newer schema refused', () async {
    final dir = await freshDir();
    await dir.libraryJson
        .writeAsString(jsonEncode({'schema_version': 2, 'games': []}));
    await expectLater(
        loadLibrary(dir),
        throwsA(isA<NewerSchema>()
            .having((e) => e.found, 'found', 2)
            .having((e) => e.supported, 'supported', 1)));
  });

  test('second writer refused', () async {
    final dir = await freshDir();
    final first = LoadedLibrary(library: Library(games: [fullGame(const Uuid().v4())]));
    await saveLibrary(dir, first);
    final a = await loadLibrary(dir);
    final b = await loadLibrary(dir);
    a.library.games.add(fullGame(const Uuid().v4()));
    await saveLibrary(dir, a);
    await expectLater(saveLibrary(dir, b), throwsA(isA<ChangedOnDisk>()));
  });

  test('two saves in one session make exactly one backup', () async {
    final dir = await freshDir();
    final loaded = LoadedLibrary(library: Library(games: [fullGame(const Uuid().v4())]));
    await saveLibrary(dir, loaded);
    final first = await dir.libraryJson.readAsString();
    loaded.library.games.add(fullGame(const Uuid().v4()));
    await saveLibrary(dir, loaded);
    loaded.library.games.add(fullGame(const Uuid().v4()));
    await saveLibrary(dir, loaded);
    final backups = await dir.backups.list().toList();
    expect(backups, hasLength(1));
    expect(await File(backups.single.path).readAsString(), equals(first));
  });

  test('a new session keeps the newest 10 and drops the oldest', () async {
    final dir = await freshDir();
    final loaded = LoadedLibrary(library: Library(games: [fullGame(const Uuid().v4())]));
    await saveLibrary(dir, loaded);
    final current = await dir.libraryJson.readAsString();
    await dir.backups.create(recursive: true);
    for (var i = 1; i <= 10; i++) {
      final name = 'library-${i.toString().padLeft(2, '0')}.json';
      await File('${dir.backups.path}/$name').writeAsString('old $i');
    }
    resetBackupSessionForTest();
    loaded.library.games.add(fullGame(const Uuid().v4()));
    await saveLibrary(dir, loaded);
    final names = <String>[];
    await for (final entry in dir.backups.list()) {
      names.add(entry.path.split('/').last);
    }
    names.sort();
    expect(names, hasLength(10));
    expect(names, isNot(contains('library-01.json')));
    expect(names, contains('library-02.json'));
    final contents = <String>{
      for (final name in names)
        await File('${dir.backups.path}/$name').readAsString(),
    };
    expect(contents, contains(current));
    expect(contents, isNot(contains('old 1')));
  });

  test('a non-matching file in backups is never deleted', () async {
    final dir = await freshDir();
    final loaded = LoadedLibrary(library: Library(games: [fullGame(const Uuid().v4())]));
    await saveLibrary(dir, loaded);
    await dir.backups.create(recursive: true);
    await File('${dir.backups.path}/notes.txt').writeAsString('keep me');
    for (var i = 1; i <= 10; i++) {
      final name = 'library-${i.toString().padLeft(2, '0')}.json';
      await File('${dir.backups.path}/$name').writeAsString('old $i');
    }
    resetBackupSessionForTest();
    loaded.library.games.add(fullGame(const Uuid().v4()));
    await saveLibrary(dir, loaded);
    expect(await File('${dir.backups.path}/notes.txt').readAsString(),
        equals('keep me'));
  });

  test('a backup failure throws and leaves library.json unchanged', () async {
    final dir = await freshDir();
    final loaded = LoadedLibrary(library: Library(games: [fullGame(const Uuid().v4())]));
    await saveLibrary(dir, loaded);
    final before = await dir.libraryJson.readAsBytes();
    await File(dir.backups.path).writeAsString('in the way');
    loaded.library.games.add(fullGame(const Uuid().v4()));
    await expectLater(saveLibrary(dir, loaded), throwsA(anything));
    expect(await dir.libraryJson.readAsBytes(), equals(before));
  });

  test('nanosecond timestamps parse', () async {
    final dir = await freshDir();
    await dir.libraryJson.writeAsString(jsonEncode({
      'schema_version': 1,
      'games': [
        {
          'id': const Uuid().v4(),
          'added_at': '2026-10-03T14:22:31.123456789+00:00',
        }
      ],
    }));
    final loaded = await loadLibrary(dir);
    final at = loaded.library.games.single.addedAt;
    expect(at.isUtc, isTrue);
    expect(at.millisecond, 123);
    expect(at.microsecond, 456);
  });

  test('playtime and last played', () {
    final game = Game(
      id: const Uuid().v4(),
      playSessions: [
        PlaySession(
            startedAt: DateTime.utc(2026, 5, 1), durationSeconds: 600),
        PlaySession(
            startedAt: DateTime.utc(2026, 5, 2), durationSeconds: 3000),
      ],
    );
    expect(game.totalPlaytimeSeconds, 3600);
    expect(game.lastPlayedAt, DateTime.utc(2026, 5, 2));
  });
}
