// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:vnl/src/core/covers.dart';
import 'package:vnl/src/core/model.dart';
import 'package:vnl/src/core/paths.dart';

String fixture(String name) => 'test/core/fixtures/covers/$name';

Uint8List fixtureBytes(String name) =>
    Uint8List.fromList(File(fixture(name)).readAsBytesSync());

DataDir freshDir() =>
    DataDir(Directory.systemTemp.createTempSync('vnl-covers-').path);

Game gameWithCover(String id, String cover) =>
    Game(id: id, title: 'Game $id', cover: cover);

Future<String> storeFixture(DataDir dir, String id, String name) =>
    storeOriginal(dir, id, fixtureBytes(name));

void main() {
  group('storeBackground', () {
    test('writes under covers/background and makes no thumbnails', () async {
      final dir = freshDir();
      final id = const Uuid().v4();
      final name = await storeBackground(dir, id, fixtureBytes('png_named.jpg'));
      expect(name, '$id.png');
      final file = File('${dir.coversBackground.path}/$id.png');
      expect(img.findFormatForData(file.readAsBytesSync()), img.ImageFormat.png);
      expect(dir.coversOriginal.existsSync(), isFalse);
      expect(File(thumbPath(dir, id, 256)).existsSync(), isFalse);
    });

    test('replaces a stored background with a different extension', () async {
      final dir = freshDir();
      final id = const Uuid().v4();
      await storeBackground(dir, id, fixtureBytes('png_named.jpg'));
      final name = await storeBackground(dir, id, fixtureBytes('tall.jpg'));
      expect(name, '$id.jpg');
      expect(File('${dir.coversBackground.path}/$id.png').existsSync(), isFalse);
      expect(File('${dir.coversBackground.path}/$id.jpg').existsSync(), isTrue);
    });

    test('rejects empty and text bytes without writing', () async {
      final dir = freshDir();
      await expectLater(
        storeBackground(dir, const Uuid().v4(), fixtureBytes('empty.jpg')),
        throwsA(isA<CoverException>().having(
            (e) => e.error, 'error', CoverError.unknownFormat)),
      );
      await expectLater(
        storeBackground(dir, const Uuid().v4(), fixtureBytes('text.jpg')),
        throwsA(isA<CoverException>().having(
            (e) => e.error, 'error', CoverError.unknownFormat)),
      );
      expect(dir.coversBackground.existsSync(), isFalse);
    });
  });

  group('storeOriginal', () {
    test('png named jpg stored as png', () async {
      final dir = freshDir();
      final id = const Uuid().v4();
      final name = await storeOriginal(dir, id, fixtureBytes('png_named.jpg'));
      expect(name, '$id.png');
      final file = File('${dir.coversOriginal.path}/$id.png');
      expect(file.existsSync(), isTrue);
      expect(img.findFormatForData(file.readAsBytesSync()), img.ImageFormat.png);
    });

    test('empty and text rejected', () async {
      final dir = freshDir();
      final id = const Uuid().v4();
      await expectLater(
        storeOriginal(dir, id, fixtureBytes('empty.jpg')),
        throwsA(isA<CoverException>().having(
            (e) => e.error, 'error', CoverError.unknownFormat)),
      );
      await expectLater(
        storeOriginal(dir, const Uuid().v4(), fixtureBytes('text.jpg')),
        throwsA(isA<CoverException>().having(
            (e) => e.error, 'error', CoverError.unknownFormat)),
      );
      expect(dir.coversOriginal.existsSync(), isFalse);
    });

    test('replacing an original clears its thumbs', () async {
      final dir = freshDir();
      final id = const Uuid().v4();
      final first = await storeFixture(dir, id, 'tall.jpg');
      await writeThumbnails(dir, id, first);
      expect(File(thumbPath(dir, id, 256)).existsSync(), isTrue);
      expect(File(thumbPath(dir, id, 512)).existsSync(), isTrue);
      final second = await storeFixture(dir, id, 'small.webp');
      expect(second, '$id.webp');
      expect(File('${dir.coversOriginal.path}/$first').existsSync(), isFalse);
      expect(File(thumbPath(dir, id, 256)).existsSync(), isFalse);
      expect(File(thumbPath(dir, id, 512)).existsSync(), isFalse);
    });
  });

  group('writeThumbnails', () {
    test('thumbs have target widths', () async {
      final dir = freshDir();
      final id = const Uuid().v4();
      final original = await storeFixture(dir, id, 'tall.jpg');
      await writeThumbnails(dir, id, original);
      final source = img.decodeImage(fixtureBytes('tall.jpg'))!;
      for (final width in thumbWidths) {
        final bytes = File(thumbPath(dir, id, width)).readAsBytesSync();
        expect(img.findFormatForData(bytes), img.ImageFormat.webp);
        final thumb = img.decodeImage(bytes)!;
        expect(thumb.width, width);
        expect((thumb.height - thumb.width).abs(), lessThanOrEqualTo(1));
        expect(
          (thumb.height / thumb.width - source.height / source.width).abs(),
          lessThan(0.01),
        );
      }
    });

    test('no partial thumbnail at final path', () async {
      final dir = freshDir();
      final id = const Uuid().v4();
      final original = await storeFixture(dir, id, 'tall.jpg');
      final renamed = <String>[];
      await writeThumbnails(dir, id, original,
          onBeforeRename: (finalPath, tmpPath) {
        expect(File(finalPath).existsSync(), isFalse);
        expect(File(tmpPath).existsSync(), isTrue);
        expect(tmpPath, endsWith('.tmp'));
        renamed.add(tmpPath);
      });
      expect(renamed, hasLength(thumbWidths.length));
      for (final width in thumbWidths) {
        expect(File(thumbPath(dir, id, width)).existsSync(), isTrue);
      }
      final leftovers = Directory(
              '${dir.root}/covers/thumb/v$thumbPipelineVersion')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.tmp'));
      expect(leftovers, isEmpty);
    });

    test('no upscale', () async {
      final dir = freshDir();
      final id = const Uuid().v4();
      final original = await storeFixture(dir, id, 'small.webp');
      await writeThumbnails(dir, id, original);
      for (final width in thumbWidths) {
        final thumb = img.decodeImage(
            File(thumbPath(dir, id, width)).readAsBytesSync())!;
        expect(thumb.width, 200);
      }
    });
  });

  group('ensureThumbnails', () {
    test('ensure does nothing when complete', () async {
      final dir = freshDir();
      final ids = [const Uuid().v4(), const Uuid().v4()];
      final library = Library(games: [
        gameWithCover(ids[0], await storeFixture(dir, ids[0], 'tall.jpg')),
        gameWithCover(ids[1], await storeFixture(dir, ids[1], 'small.webp')),
      ]);
      final first = await ensureThumbnails(dir, library);
      expect(first.generated, 2);
      expect(first.failed, isEmpty);
      final stamps = {
        for (final id in ids)
          for (final w in thumbWidths)
            thumbPath(dir, id, w):
                File(thumbPath(dir, id, w)).lastModifiedSync(),
      };
      final second = await ensureThumbnails(dir, library);
      expect(second.generated, 0);
      expect(second.failed, isEmpty);
      for (final entry in stamps.entries) {
        expect(File(entry.key).lastModifiedSync(), entry.value);
      }
    });

    test('ensure regenerates only missing', () async {
      final dir = freshDir();
      final id = const Uuid().v4();
      final library = Library(
          games: [gameWithCover(id, await storeFixture(dir, id, 'tall.jpg'))]);
      await ensureThumbnails(dir, library);
      File(thumbPath(dir, id, 512)).deleteSync();
      final report = await ensureThumbnails(dir, library);
      expect(report.generated, 1);
      expect(report.failed, isEmpty);
      expect(File(thumbPath(dir, id, 256)).existsSync(), isTrue);
      expect(File(thumbPath(dir, id, 512)).existsSync(), isTrue);
    });

    test('bad original reported', () async {
      final dir = freshDir();
      final badId = const Uuid().v4();
      final goodId = const Uuid().v4();
      await dir.coversOriginal.create(recursive: true);
      File('${dir.coversOriginal.path}/$badId.jpg')
          .writeAsBytesSync(fixtureBytes('truncated.jpg'));
      final library = Library(games: [
        gameWithCover(badId, '$badId.jpg'),
        gameWithCover(goodId, await storeFixture(dir, goodId, 'tall.jpg')),
      ]);
      final report = await ensureThumbnails(dir, library);
      expect(report.generated, 1);
      expect(report.failed.map((f) => f.$1), [badId]);
      expect(File(thumbPath(dir, goodId, 256)).existsSync(), isTrue);
      expect(File(thumbPath(dir, goodId, 512)).existsSync(), isTrue);
    });
  });

  group('ensureThumbnails tmp debris', () {
    test('leftover tmp file is ignored and final is regenerated', () async {
      final dir = freshDir();
      final id = const Uuid().v4();
      final library = Library(
          games: [gameWithCover(id, await storeFixture(dir, id, 'tall.jpg'))]);
      await ensureThumbnails(dir, library);
      File(thumbPath(dir, id, 512)).deleteSync();
      File('${thumbPath(dir, id, 512)}.$pid.tmp')
          .writeAsBytesSync([1, 2, 3]);
      final report = await ensureThumbnails(dir, library);
      expect(report.generated, 1);
      expect(report.failed, isEmpty);
      final thumb = img.decodeImage(
          File(thumbPath(dir, id, 512)).readAsBytesSync())!;
      expect(thumb.width, 512);
    });
  });

  group('generateThumbnails', () {
    test('pool keeps workers busy', () async {
      final dir = freshDir();
      final noisy = img.Image(width: 1600, height: 1600);
      final rng = Random(1234);
      for (var y = 0; y < noisy.height; y++) {
        for (var x = 0; x < noisy.width; x++) {
          noisy.setPixelRgb(
              x, y, rng.nextInt(256), rng.nextInt(256), rng.nextInt(256));
        }
      }
      final slowId = const Uuid().v4();
      final slowName =
          await storeOriginal(dir, slowId, Uint8List.fromList(img.encodeJpg(noisy)));
      expect(slowName, '$slowId.jpg');
      final jobs = <(String, String)>[(slowId, slowName)];
      for (var i = 0; i < 3; i++) {
        final id = const Uuid().v4();
        jobs.add((id, await storeFixture(dir, id, 'small.webp')));
      }
      final seen = <(int, int)>[];
      var slowCompleteAtDone3 = true;
      final report = await generateThumbnails(dir, jobs,
          concurrency: 2, onProgress: (done, total) {
        seen.add((done, total));
        if (done == 3) {
          slowCompleteAtDone3 =
              File(thumbPath(dir, slowId, 256)).existsSync() &&
                  File(thumbPath(dir, slowId, 512)).existsSync();
        }
      });
      expect(report.generated, 4);
      expect(report.failed, isEmpty);
      expect(seen, hasLength(4));
      expect(seen.last, (4, 4));
      expect(slowCompleteAtDone3, isFalse,
          reason: 'slow job still running while 3 small jobs finished');
    });

    test('onProgress capturing an unsendable object works', () async {
      final dir = freshDir();
      final jobs = <(String, String)>[];
      for (var i = 0; i < 2; i++) {
        final id = const Uuid().v4();
        jobs.add((id, await storeFixture(dir, id, 'tall.jpg')));
      }
      final port = ReceivePort();
      final seen = <(int, int)>[];
      final report = await generateThumbnails(dir, jobs,
          concurrency: 2, onProgress: (done, total) {
        port.sendPort.send(done);
        seen.add((done, total));
      });
      expect(report.generated, 2);
      expect(report.failed, isEmpty);
      expect(seen, hasLength(2));
      expect(seen.last, (2, 2));
      port.close();
    });

    test('pool reports progress', () async {
      final dir = freshDir();
      final jobs = <(String, String)>[];
      for (var i = 0; i < 4; i++) {
        final id = const Uuid().v4();
        jobs.add((id, await storeFixture(dir, id, 'tall.jpg')));
      }
      final seen = <(int, int)>[];
      final report = await generateThumbnails(dir, jobs,
          concurrency: 2, onProgress: (done, total) => seen.add((done, total)));
      expect(report.generated, 4);
      expect(report.failed, isEmpty);
      expect(seen, hasLength(4));
      expect(seen.last, (4, 4));
    });
  });
}
