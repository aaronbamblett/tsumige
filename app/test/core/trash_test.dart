// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:tsumige/src/core/covers.dart';
import 'package:tsumige/src/core/model.dart';
import 'package:tsumige/src/core/paths.dart';
import 'package:tsumige/src/core/trash.dart';

DataDir _dir(Directory temp) => DataDir(temp.path);

Game _game(String id) => Game(id: id, title: 'Alpha', cover: '$id.png');

Future<void> _writeCover(DataDir dir, String gameId) async {
  final bytes = Uint8List.fromList(
      img.encodePng(img.Image(width: 8, height: 8)));
  await dir.coversOriginal.create(recursive: true);
  await File(p.join(dir.coversOriginal.path, '$gameId.png'))
      .writeAsBytes(bytes);
  await generateThumbnails(dir, [(gameId, '$gameId.png')]);
}

void main() {
  test('game json and cover files move into trash/<ts>-<id>/', () async {
    final temp = Directory.systemTemp.createTempSync('tsumige_trash_test_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final dir = _dir(temp);
    const id = '11111111-1111-4111-8111-111111111111';
    final game = _game(id);
    await _writeCover(dir, id);

    await moveToTrash(dir, game,
        now: DateTime.utc(2026, 10, 17, 8, 30, 5, 123));

    final folder = Directory(
        p.join(dir.trash.path, '20261017T083005.123Z-$id'));
    expect(folder.existsSync(), isTrue);
    final stored =
        jsonDecode(File(p.join(folder.path, 'game.json')).readAsStringSync())
            as Map;
    expect(stored['id'], id);
    expect(stored['title'], 'Alpha');
    expect(File(p.join(folder.path, '$id.png')).existsSync(), isTrue);
    expect(File(p.join(folder.path, 'thumb-256.webp')).existsSync(), isTrue);
    expect(File(p.join(folder.path, 'thumb-512.webp')).existsSync(), isTrue);
    expect(File(p.join(dir.coversOriginal.path, '$id.png')).existsSync(),
        isFalse);
    expect(File(thumbPath(dir, id, 256)).existsSync(), isFalse);
    expect(File(thumbPath(dir, id, 512)).existsSync(), isFalse);
  });

  test('a game background moves into the same trash folder', () async {
    final temp = Directory.systemTemp.createTempSync('tsumige_trash_test_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final dir = _dir(temp);
    const id = '33333333-3333-4333-8333-333333333333';
    final game = Game(id: id, title: 'Alpha', background: '$id.jpg');
    await dir.coversBackground.create(recursive: true);
    File(p.join(dir.coversBackground.path, '$id.jpg'))
        .writeAsBytesSync([1, 2, 3]);

    await moveToTrash(dir, game,
        now: DateTime.utc(2026, 10, 17, 8, 30, 5, 123));

    final folder = Directory(
        p.join(dir.trash.path, '20261017T083005.123Z-$id'));
    expect(File(p.join(folder.path, 'background-$id.jpg')).readAsBytesSync(),
        [1, 2, 3]);
    expect(File(p.join(dir.coversBackground.path, '$id.jpg')).existsSync(),
        isFalse);
  });

  test('trashBackground moves only the background and keeps the cover',
      () async {
    final temp = Directory.systemTemp.createTempSync('tsumige_trash_test_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final dir = _dir(temp);
    const id = '44444444-4444-4444-8444-444444444444';
    final game = Game(id: id, title: 'Alpha', cover: '$id.png', background: '$id.png');
    await _writeCover(dir, id);
    await dir.coversBackground.create(recursive: true);
    File(p.join(dir.coversBackground.path, '$id.png'))
        .writeAsBytesSync([4, 5]);

    await trashBackground(dir, game,
        now: DateTime.utc(2026, 10, 17, 8, 30, 5, 123));

    final folder = Directory(
        p.join(dir.trash.path, '20261017T083005.123Z-$id'));
    expect(File(p.join(folder.path, 'background-$id.png')).readAsBytesSync(),
        [4, 5]);
    expect(File(p.join(dir.coversBackground.path, '$id.png')).existsSync(),
        isFalse);
    expect(File(p.join(dir.coversOriginal.path, '$id.png')).existsSync(),
        isTrue);
  });

  test('a missing cover file does not throw', () async {
    final temp = Directory.systemTemp.createTempSync('tsumige_trash_test_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final dir = _dir(temp);
    const id = '22222222-2222-4222-8222-222222222222';
    final game = _game(id);

    await moveToTrash(dir, game);

    final entries = dir.trash.listSync();
    expect(entries, hasLength(1));
    final folder = entries.single as Directory;
    expect(p.basename(folder.path).endsWith('-$id'), isTrue);
    expect(File(p.join(folder.path, 'game.json')).existsSync(), isTrue);
  });
}
