// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'covers.dart';
import 'model.dart';
import 'paths.dart';

String trashFolderName(DateTime utc, String id) {
  String two(int n) => n.toString().padLeft(2, '0');
  String three(int n) => n.toString().padLeft(3, '0');
  return '${utc.year}${two(utc.month)}${two(utc.day)}'
      'T${two(utc.hour)}${two(utc.minute)}${two(utc.second)}.'
      '${three(utc.millisecond)}Z-$id';
}

Future<void> _moveIfPresent(String from, String to) async {
  final file = File(from);
  if (!await file.exists()) return;
  await Directory(p.dirname(to)).create(recursive: true);
  await file.rename(to);
}

/// Moves a game's entry and cover files into `trash/` in the data folder.
/// Nothing is ever permanently deleted; restore is by hand.
Future<void> moveToTrash(DataDir dir, Game game, {DateTime? now}) async {
  final folder = Directory(p.join(
      dir.trash.path, trashFolderName((now ?? DateTime.now()).toUtc(), game.id)));
  await folder.create(recursive: true);
  await File(p.join(folder.path, 'game.json'))
      .writeAsString(jsonEncode(game.toJson()), flush: true);
  final cover = game.cover;
  if (cover != null && cover.isNotEmpty) {
    await _moveIfPresent(p.join(dir.coversOriginal.path, cover),
        p.join(folder.path, cover));
  }
  for (final width in thumbWidths) {
    await _moveIfPresent(
        thumbPath(dir, game.id, width), p.join(folder.path, 'thumb-$width.webp'));
  }
  await _moveBackgroundIfSet(dir, game, folder);
}

/// Moves a game's pane background into a new trash folder, for when the
/// user drops a background and keeps the cover.
Future<void> trashBackground(DataDir dir, Game game, {DateTime? now}) async {
  final folder = Directory(p.join(
      dir.trash.path, trashFolderName((now ?? DateTime.now()).toUtc(), game.id)));
  await _moveBackgroundIfSet(dir, game, folder);
}

Future<void> _moveBackgroundIfSet(DataDir dir, Game game, Directory folder) async {
  final background = game.background;
  if (background == null || background.isEmpty) return;
  await _moveIfPresent(p.join(dir.coversBackground.path, background),
      p.join(folder.path, 'background-$background'));
}
