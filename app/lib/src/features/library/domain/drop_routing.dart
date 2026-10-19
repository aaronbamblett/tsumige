// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:path/path.dart' as p;

/// What dropping files or folders starts.
sealed class DropRoute {
  const DropRoute();
}

/// One game: its folder, and the game file when a file was dropped.
class DropMatch extends DropRoute {
  const DropMatch({required this.folder, this.file});

  final String folder;
  final String? file;
}

/// Several folders to import, each a root to scan.
class DropImport extends DropRoute {
  const DropImport(this.roots);

  final List<String> roots;
}

/// Routes dropped [paths]: one folder or file is a single game, and several
/// items are an import of their folders (a file counts as its parent folder).
/// A single folder holding several games imports with that folder as its root.
///
/// [countGames] is the fast early-exit probe (0, 1, or 2 meaning two or
/// more): the full import scan must not run before the destination opens.
Future<DropRoute?> routeDrop(
  List<String> paths, {
  required bool Function(String path) isDirectory,
  required Future<int> Function(String path) countGames,
}) async {
  if (paths.isEmpty) return null;
  if (paths.length == 1) {
    final path = paths.single;
    if (!isDirectory(path)) {
      return DropMatch(folder: p.dirname(path), file: path);
    }
    int count;
    try {
      count = await countGames(path);
    } on FileSystemException {
      count = 0;
    }
    if (count >= 2) return DropImport([path]);
    return DropMatch(folder: path);
  }
  return DropImport([
    for (final path in <String>{
      for (final path in paths) isDirectory(path) ? path : p.dirname(path),
    })
      path,
  ]);
}
