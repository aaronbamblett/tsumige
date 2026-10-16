// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';
import 'package:vnl_core/vnl_core.dart';

String fixture(String name) => 'test/fixtures/covers/$name';

Uint8List fixtureBytes(String name) =>
    Uint8List.fromList(File(fixture(name)).readAsBytesSync());

DataDir freshDir() =>
    DataDir(Directory.systemTemp.createTempSync('vnl-covers-').path);

Game gameWithCover(String id, String cover) =>
    Game(id: id, title: 'Game $id', cover: cover);

Future<String> storeFixture(DataDir dir, String id, String name) =>
    storeOriginal(dir, id, fixtureBytes(name));

void main() {
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

  group('generateThumbnails', () {
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
