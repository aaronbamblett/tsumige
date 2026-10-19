// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumige/src/features/library/domain/drop_routing.dart';

bool _isDir(String path) => !path.endsWith('.exe');

Future<int> Function(String) _count(Map<String, int> games) =>
    (path) async => games[path] ?? 0;

Future<int> _noCount(String path) => throw StateError('must not probe $path');

Future<int> _failingCount(String path) {
  throw FileSystemException('unreadable', path);
}

void main() {
  test('nothing dropped routes nowhere', () async {
    expect(
      await routeDrop(const [], isDirectory: _isDir, countGames: _noCount),
      isNull,
    );
  });

  test('one folder with one game is a single game with that folder', () async {
    final route =
        (await routeDrop(
              ['/games/Alpha'],
              isDirectory: _isDir,
              countGames: _count({'/games/Alpha': 1}),
            ))!;
    expect(route, isA<DropMatch>());
    final match = route as DropMatch;
    expect(match.folder, '/games/Alpha');
    expect(match.file, isNull);
  });

  test('one folder with no games is a single game with that folder', () async {
    final route =
        (await routeDrop(
              ['/games/Alpha'],
              isDirectory: _isDir,
              countGames: _count({'/games/Alpha': 0}),
            ))!;
    expect(route, isA<DropMatch>());
    expect((route as DropMatch).folder, '/games/Alpha');
  });

  test('one folder with several games imports with that folder as the root', () async {
    final route =
        (await routeDrop(
              ['/games/Story'],
              isDirectory: _isDir,
              countGames: _count({'/games/Story': 2}),
            ))!;
    expect(route, isA<DropImport>());
    expect((route as DropImport).roots, ['/games/Story']);
  });

  test('a probe failure is a single game with that folder', () async {
    final route =
        (await routeDrop(
              ['/games/Alpha'],
              isDirectory: _isDir,
              countGames: _failingCount,
            ))!;
    expect(route, isA<DropMatch>());
    expect((route as DropMatch).folder, '/games/Alpha');
  });

  test('one game file matches its parent folder with that file', () async {
    final match =
        (await routeDrop(
              ['/games/Alpha/Alpha.exe'],
              isDirectory: _isDir,
              countGames: _noCount,
            ))!
            as DropMatch;
    expect(match.folder, '/games/Alpha');
    expect(match.file, '/games/Alpha/Alpha.exe');
  });

  test('several folders import with those folders as the roots', () async {
    final route =
        (await routeDrop(
              ['/games/Alpha', '/games/Beta'],
              isDirectory: _isDir,
              countGames: _noCount,
            ))!
            as DropImport;
    expect(route.roots, ['/games/Alpha', '/games/Beta']);
  });

  test('several items import their folders, a file counting as its parent', () async {
    final route =
        (await routeDrop(
              [
                '/games/Alpha',
                '/games/Beta/Beta.exe',
                '/games/Beta/Beta.exe',
              ],
              isDirectory: _isDir,
              countGames: _noCount,
            ))!
            as DropImport;
    expect(route.roots, ['/games/Alpha', '/games/Beta']);
  });
}
