// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumige/src/features/library/domain/drop_routing.dart';
import 'package:tsumige/src/features/library/domain/folder_import.dart';

bool _isDir(String path) => !path.endsWith('.exe');

Future<List<ImportFolder>> Function(String) _scan(Map<String, int> games) =>
    (path) async => [
      for (var i = 0; i < (games[path] ?? 0); i++)
        ImportFolder(name: 'Game$i', path: '$path/Game$i', exes: const []),
    ];

Future<List<ImportFolder>> _noScan(String path) =>
    throw StateError('must not scan $path');

void main() {
  test('nothing dropped routes nowhere', () async {
    expect(
      await routeDrop(const [], isDirectory: _isDir, scanFolder: _noScan),
      isNull,
    );
  });

  test('one folder with one game is a single game with that folder', () async {
    final route =
        (await routeDrop(
              ['/games/Alpha'],
              isDirectory: _isDir,
              scanFolder: _scan({'/games/Alpha': 1}),
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
              scanFolder: _scan({'/games/Alpha': 0}),
            ))!;
    expect(route, isA<DropMatch>());
    expect((route as DropMatch).folder, '/games/Alpha');
  });

  test('one folder with several games imports with that folder as the root', () async {
    final route =
        (await routeDrop(
              ['/games/Story'],
              isDirectory: _isDir,
              scanFolder: _scan({'/games/Story': 3}),
            ))!;
    expect(route, isA<DropImport>());
    expect((route as DropImport).roots, ['/games/Story']);
  });

  test('one game file matches its parent folder with that file', () async {
    final match =
        (await routeDrop(
              ['/games/Alpha/Alpha.exe'],
              isDirectory: _isDir,
              scanFolder: _noScan,
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
              scanFolder: _noScan,
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
              scanFolder: _noScan,
            ))!
            as DropImport;
    expect(route.roots, ['/games/Alpha', '/games/Beta']);
  });
}
