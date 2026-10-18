// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumige/src/core/covers.dart' as core;
import 'package:tsumige/src/core/model.dart' as core;
import 'package:tsumige/src/core/paths.dart' as core;
import 'package:tsumige/src/core/vndb.dart' as core;
import 'package:tsumige/src/features/library/data/library_repository.dart';
import 'package:tsumige/src/features/library/domain/add_game.dart';
import 'package:tsumige/src/features/library/domain/game_editor.dart';
import 'package:tsumige/src/features/library/presentation/widgets/art_picker_dialog.dart';
import 'package:tsumige/src/utils/prefs/prefs_mixin.dart';
import 'package:tsumige/src/utils/theme/brand.dart';
import 'package:tsumige/src/widgets/tsumige_logo.dart';

const _main = {
  'url': 'https://t.vndb.org/cv/16/98416.jpg',
  'thumbnail': 'https://t.vndb.org/cv.t/16/98416.jpg',
  'dims': [411, 560],
};
const _portrait = {
  'type': 'pkgfront',
  'url': 'https://t.vndb.org/cv/66/98366.jpg',
  'thumbnail': 'https://t.vndb.org/cv.t/66/98366.jpg',
  'dims': [350, 500],
};
const _landscape = {
  'type': 'dig',
  'url': 'https://t.vndb.org/cv/64/98364.jpg',
  'thumbnail': 'https://t.vndb.org/cv.t/64/98364.jpg',
  'dims': [1368, 770],
};
const _shotOne = {
  'url': 'https://t.vndb.org/sf/86/101386.jpg',
  'thumbnail': 'https://t.vndb.org/sf.t/86/101386.jpg',
  'dims': [1024, 768],
};
const _shotTwo = {
  'url': 'https://t.vndb.org/sf/87/101387.jpg',
  'thumbnail': 'https://t.vndb.org/sf.t/87/101387.jpg',
  'dims': [1024, 768],
};

/// Canned VNDB answers for `/vn` and `/release`; every other host serves a
/// PNG. [downloads] records each image url fetched. [brokenShot] makes the
/// first screenshot answer with bytes that are not an image.
http.Client _fakeHttp({
  required bool Function() vndbFails,
  bool Function()? brokenShot,
  List<String>? downloads,
}) {
  final png = Uint8List.fromList(
    img.encodePng(img.Image(width: 16, height: 16)),
  );
  return MockClient((request) async {
    if (request.url.host != 'api.vndb.org') {
      final url = request.url.toString();
      downloads?.add(url);
      if (brokenShot != null && brokenShot() && url == _shotOne['url']) {
        return http.Response('not an image', 200);
      }
      return http.Response.bytes(
        png,
        200,
        headers: {'content-type': 'image/png'},
      );
    }
    if (request.url.path.endsWith('/vn')) {
      if (vndbFails()) return http.Response('boom', 500);
      return http.Response(
        jsonEncode({
          'results': [
            {
              'image': _main,
              'screenshots': [_shotOne, _shotTwo],
            },
          ],
          'more': false,
        }),
        200,
      );
    }
    if (request.url.path.endsWith('/release')) {
      return http.Response(
        jsonEncode({
          'results': [
            {
              'images': [
                {..._main, 'type': 'main'},
                _landscape,
                _portrait,
              ],
            },
          ],
          'more': false,
        }),
        200,
      );
    }
    return http.Response('not found', 404);
  });
}

class PickerFakeRepository implements LibraryRepository {
  PickerFakeRepository(this.loaded);

  final core.LoadedLibrary loaded;

  @override
  Future<core.LoadedLibrary> load() async => loaded;

  @override
  Future<void> save(core.LoadedLibrary loaded) async {}

  @override
  Future<core.VndbRefreshReport> refreshVndbData(
    core.LoadedLibrary loaded,
  ) async => const core.VndbRefreshReport();

  @override
  Future<core.ThumbReport> ensureThumbnails(core.Library library) async =>
      core.ThumbReport();
}

/// Real file work never finishes inside the fake-async test zone, so these
/// flows run in `runAsync`, polling for the file effect before asserting.
Future<void> runRealFlow(
  WidgetTester tester,
  Future<void> Function() flow,
  bool Function() done,
) async {
  await tester.runAsync(() async {
    await flow();
    for (var i = 0; i < 200 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  });
  expect(done(), isTrue);
  await tester.pumpAndSettle();
}

/// Lets the fake VNDB answer land; the progress spinner keeps animating, so
/// `pumpAndSettle` is not usable until the grid is up.
Future<void> settleVndb(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

class _Harness {
  _Harness(this.tester, this.temp, this.loaded);

  final WidgetTester tester;
  final Directory temp;
  final core.LoadedLibrary loaded;

  core.DataDir get dir => core.DataDir(temp.path);
  core.Game get game => loaded.library.games.single;

  Future<void> open({
    core.Game? game,
    http.Client? http,
    Future<String?> Function()? picker,
    Size size = const Size(1400, 980),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
          dataDirProvider.overrideWithValue(dir),
          libraryRepositoryProvider.overrideWithValue(
            PickerFakeRepository(loaded),
          ),
          addGameHttpClientProvider.overrideWithValue(
            http ?? _fakeHttp(vndbFails: () => false),
          ),
          if (picker != null) coverPickerProvider.overrideWithValue(picker),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) {
              ref.watch(libraryProvider);
              return Scaffold(
                body: Builder(
                  builder: (context) => Center(
                    child: ElevatedButton(
                      onPressed: () =>
                          showArtPickerDialog(context, game ?? this.game),
                      child: const Text('open'),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump();
  }
}

Finder _tile(String url) => find.byKey(ValueKey('art-$url'));

Finder _pill(String url) =>
    find.descendant(of: _tile(url), matching: find.text('Current'));

List<String> _tileUrls(WidgetTester tester) => [
  for (final w in tester.widgetList(
    find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('art-https'),
    ),
  ))
    (w.key as ValueKey<String>).value.substring('art-'.length),
];

Future<_Harness> _pumpDialog(
  WidgetTester tester, {
  core.Game? game,
  String? vndbId = 'v900016',
  String? background,
  String? cover,
  String? coverSource,
  String? backgroundSource,
  bool Function()? vndbFails,
  Future<String?> Function()? picker,
}) async {
  final temp = Directory.systemTemp.createTempSync('tsumige_art_picker_');
  addTearDown(() => temp.deleteSync(recursive: true));
  final g =
      game ??
      core.Game(
        id: 'g1',
        title: 'Sample Game',
        vndbId: vndbId,
        cover: cover,
        background: background,
        coverSource: coverSource,
        backgroundSource: backgroundSource,
      );
  final loaded = core.LoadedLibrary(library: core.Library(games: [g]));
  final harness = _Harness(tester, temp, loaded);
  await harness.open(
    game: g,
    http: _fakeHttp(vndbFails: vndbFails ?? () => false),
    picker: picker,
  );
  await settleVndb(tester);
  return harness;
}

Uint8List _png() =>
    Uint8List.fromList(img.encodePng(img.Image(width: 16, height: 16)));

void main() {
  testWidgets('the loading state shows the 48 px logo shimmer', (tester) async {
    final temp = Directory.systemTemp.createTempSync('tsumige_art_loading_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final g = core.Game(id: 'g1', title: 'Sample Game', vndbId: 'v900016');
    final harness = _Harness(
      tester,
      temp,
      core.LoadedLibrary(library: core.Library(games: [g])),
    );
    await harness.open(
      game: g,
      http: MockClient((_) => Completer<http.Response>().future),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.getSize(find.byType(TsumigeLogoShimmer)), const Size(48, 48));
  });

  testWidgets(
    'cover tab lists main, then portrait, then landscape release images',
    (tester) async {
      await _pumpDialog(tester);
      expect(_tileUrls(tester), [
        _main['url'],
        _portrait['url'],
        _landscape['url'],
      ]);
      expect(find.text('VNDB covers and packages'), findsOneWidget);
    },
  );

  testWidgets(
    'background tab shows screenshots, then artwork without portrait images',
    (tester) async {
      await _pumpDialog(tester);
      await tester.tap(find.text('Background'));
      await tester.pump();
      expect(_tileUrls(tester), [
        _shotOne['url'],
        _shotTwo['url'],
        _main['url'],
        _landscape['url'],
      ]);
      expect(find.text('VNDB screenshots'), findsOneWidget);
      expect(find.text('VNDB artwork'), findsOneWidget);
    },
  );

  testWidgets(
    'Save stores the picked cover and background, recording their sources',
    (tester) async {
      final harness = await _pumpDialog(tester);
      final dir = harness.dir;
      await tester.tap(_tile(_portrait['url'] as String));
      await tester.pump();
      await tester.tap(find.text('Background'));
      await tester.pump();
      await tester.tap(_tile(_shotOne['url'] as String));
      await tester.pump();
      await runRealFlow(
        tester,
        () async {
          await tester.tap(find.text('Save'));
          await tester.pump();
        },
        () =>
            harness.game.background == 'g1.png' &&
            harness.game.cover == 'g1.png',
      );
      expect(
        File(p.join(dir.coversOriginal.path, 'g1.png')).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(dir.coversBackground.path, 'g1.png')).existsSync(),
        isTrue,
      );
      expect(harness.game.coverSource, _portrait['url']);
      expect(harness.game.backgroundSource, _shotOne['url']);
      expect(find.byType(ArtPickerDialog), findsNothing);
    },
  );

  testWidgets(
    'From file… makes the file the pending cover and Save stores it',
    (tester) async {
      final temp = Directory.systemTemp.createTempSync('tsumige_art_picker_');
      addTearDown(() => temp.deleteSync(recursive: true));
      final source = File(p.join(temp.path, 'picked.png'))
        ..writeAsBytesSync(_png());
      final game = core.Game(id: 'g1', title: 'Sample Game');
      final loaded = core.LoadedLibrary(library: core.Library(games: [game]));
      final harness = _Harness(tester, temp, loaded);
      await harness.open(picker: () async => source.path);
      await tester.tap(find.text('From file…'));
      await tester.pump();
      await tester.pump();
      await runRealFlow(tester, () async {
        await tester.tap(find.text('Save'));
        await tester.pump();
      }, () => harness.game.cover == 'g1.png');
      expect(
        File(p.join(harness.dir.coversOriginal.path, 'g1.png')).existsSync(),
        isTrue,
      );
      expect(harness.game.background, isNull);
      expect(harness.game.coverSource, 'file');
    },
  );

  testWidgets(
    'Use the cover clears the background and moves its file to trash',
    (tester) async {
      final temp = Directory.systemTemp.createTempSync('tsumige_art_picker_');
      addTearDown(() => temp.deleteSync(recursive: true));
      final dir = core.DataDir(temp.path);
      dir.coversBackground.createSync(recursive: true);
      File(p.join(dir.coversBackground.path, 'g1.png'))
          .writeAsBytesSync(_png());
      final game = core.Game(
        id: 'g1',
        title: 'Sample Game',
        vndbId: 'v900016',
        background: 'g1.png',
        backgroundSource: _shotOne['url'] as String,
      );
      final loaded = core.LoadedLibrary(library: core.Library(games: [game]));
      final harness = _Harness(tester, temp, loaded);
      await harness.open(
        game: game,
        http: _fakeHttp(vndbFails: () => false),
      );
      await settleVndb(tester);
      await tester.tap(find.text('Background'));
      await tester.pump();
      await tester.tap(find.text('Use the cover'));
      await tester.pump();
      await runRealFlow(tester, () async {
        await tester.tap(find.text('Save'));
        await tester.pump();
      }, () => harness.game.background == null);
      expect(
        File(p.join(dir.coversBackground.path, 'g1.png')).existsSync(),
        isFalse,
      );
      expect(
        dir.trash
            .listSync(recursive: true)
            .any((e) => e.path.endsWith('background-g1.png')),
        isTrue,
      );
      expect(harness.game.backgroundSource, isNull);
    },
  );

  testWidgets('Cancel discards pending choices', (tester) async {
    final harness = await _pumpDialog(tester);
    await tester.tap(_tile(_portrait['url'] as String));
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(ArtPickerDialog), findsNothing);
    expect(harness.game.cover, isNull);
    expect(harness.game.background, isNull);
    expect(harness.dir.coversOriginal.existsSync(), isFalse);
  });

  testWidgets('no VNDB id shows only the file option', (tester) async {
    await _pumpDialog(tester, vndbId: null);
    expect(find.text('No VNDB id, so pick a file.'), findsOneWidget);
    expect(find.text('VNDB covers and packages'), findsNothing);
    expect(find.text('From file…'), findsOneWidget);
    expect(find.text('Use VNDB cover'), findsNothing);
  });

  testWidgets('a VNDB failure shows the message and Try again recovers', (
    tester,
  ) async {
    var failing = true;
    await _pumpDialog(tester, vndbFails: () => failing);
    expect(find.text("Couldn't reach VNDB."), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    failing = false;
    await tester.tap(find.text('Try again'));
    await settleVndb(tester);
    expect(find.text("Couldn't reach VNDB."), findsNothing);
    expect(_tileUrls(tester), contains(_main['url']));
  });

  testWidgets('the Background note shows until a background is picked', (
    tester,
  ) async {
    await _pumpDialog(tester);
    await tester.tap(find.text('Background'));
    await tester.pump();
    expect(
      find.text('No background picked, so the pane uses the cover.'),
      findsOneWidget,
    );
    expect(find.text('Use the cover'), findsNothing);
    await tester.tap(_tile(_shotOne['url'] as String));
    await tester.pump();
    expect(
      find.text('No background picked, so the pane uses the cover.'),
      findsNothing,
    );
    expect(find.text('Use the cover'), findsOneWidget);
  });

  testWidgets('a portal file path is rejected with a toast', (tester) async {
    await _pumpDialog(
      tester,
      vndbId: null,
      picker: () async => '/run/user/1000/docs/c.png',
    );
    await tester.tap(find.text('From file…'));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Flatpak portal'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('buttons are Brand buttons by type', (tester) async {
    await _pumpDialog(tester);
    expect(find.widgetWithText(BrandButton, 'Save'), findsOneWidget);
    expect(find.widgetWithText(BrandGlassButton, 'Cancel'), findsOneWidget);
    expect(find.widgetWithText(BrandGlassButton, 'From file…'), findsOneWidget);
    expect(
      find.widgetWithText(BrandGlassButton, 'Use VNDB cover'),
      findsOneWidget,
    );
  });

  testWidgets('the dialog is 960 by 720 at 1400 by 980', (tester) async {
    await _pumpDialog(tester);
    expect(
      tester.getSize(find.byKey(const Key('art-picker'))),
      const Size(960, 720),
    );
  });

  testWidgets('nothing overflows at 1000 by 640', (tester) async {
    final temp = Directory.systemTemp.createTempSync('tsumige_art_picker_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final game = core.Game(id: 'g1', title: 'Sample Game', vndbId: 'v900016');
    final loaded = core.LoadedLibrary(library: core.Library(games: [game]));
    final harness = _Harness(tester, temp, loaded);
    await harness.open(
      game: game,
      http: _fakeHttp(vndbFails: () => false),
      size: const Size(1000, 640),
    );
    await settleVndb(tester);
    await tester.tap(find.text('Background'));
    await tester.pump();
    expect(
      tester.getSize(find.byKey(const Key('art-picker'))),
      const Size(900, 576),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a retry after a failed background does not download the cover again',
    (tester) async {
      final downloads = <String>[];
      var brokenShot = true;
      final temp = Directory.systemTemp.createTempSync('tsumige_art_picker_');
      addTearDown(() => temp.deleteSync(recursive: true));
      final game = core.Game(id: 'g1', title: 'Sample Game', vndbId: 'v900016');
      final loaded = core.LoadedLibrary(library: core.Library(games: [game]));
      final harness = _Harness(tester, temp, loaded);
      await harness.open(
        game: game,
        http: _fakeHttp(
          vndbFails: () => false,
          brokenShot: () => brokenShot,
          downloads: downloads,
        ),
      );
      await settleVndb(tester);
      await tester.tap(_tile(_portrait['url'] as String));
      await tester.pump();
      await tester.tap(find.text('Background'));
      await tester.pump();
      await tester.tap(_tile(_shotOne['url'] as String));
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(find.text('Save'));
        await tester.pump();
        for (var i = 0; i < 200 && game.cover == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
        for (var i = 0; i < 40; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
      });
      await tester.pump();
      expect(game.cover, 'g1.png');
      expect(game.background, isNull);
      expect(find.byType(ArtPickerDialog), findsOneWidget);
      expect(find.textContaining("Couldn't use that image"), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));

      brokenShot = false;
      await runRealFlow(tester, () async {
        await tester.tap(find.text('Save'));
        await tester.pump();
      }, () => game.background == 'g1.png');
      expect(downloads.where((u) => u == _portrait['url']), hasLength(1));
      expect(downloads.where((u) => u == _shotOne['url']), hasLength(2));
      expect(game.backgroundSource, _shotOne['url']);
      await tester.pump(const Duration(seconds: 6));
    },
  );

  group('Current pill', () {
    testWidgets(
      'a migrated cover with no source is current on the VNDB main tile',
      (tester) async {
        await _pumpDialog(tester, cover: 'g1.png');
        expect(_pill(_main['url'] as String), findsOneWidget);
        expect(_pill(_portrait['url'] as String), findsNothing);
      },
    );

    testWidgets('the recorded cover source is the current tile', (
      tester,
    ) async {
      await _pumpDialog(
        tester,
        cover: 'g1.png',
        coverSource: _portrait['url'] as String,
      );
      expect(_pill(_portrait['url'] as String), findsOneWidget);
      expect(_pill(_main['url'] as String), findsNothing);
    });

    testWidgets('a local file cover marks no VNDB tile', (tester) async {
      await _pumpDialog(tester, cover: 'g1.png', coverSource: 'file');
      expect(find.text('Current'), findsNothing);
    });

    testWidgets(
      'with no background the Background tab marks the cover source',
      (tester) async {
        await _pumpDialog(tester, cover: 'g1.png');
        await tester.tap(find.text('Background'));
        await tester.pump();
        expect(_pill(_main['url'] as String), findsOneWidget);
        expect(_pill(_shotOne['url'] as String), findsNothing);
      },
    );

    testWidgets('the Background tab marks the background source', (
      tester,
    ) async {
      await _pumpDialog(
        tester,
        cover: 'g1.png',
        background: 'g1.png',
        backgroundSource: _shotOne['url'] as String,
      );
      await tester.tap(find.text('Background'));
      await tester.pump();
      expect(_pill(_shotOne['url'] as String), findsOneWidget);
      expect(_pill(_main['url'] as String), findsNothing);
    });

    testWidgets('a game with no cover shows no pill', (tester) async {
      await _pumpDialog(tester);
      expect(find.text('Current'), findsNothing);
    });
  });

  group('whole-image tiles', () {
    testWidgets("a tile's image uses BoxFit.contain", (tester) async {
      await _pumpDialog(tester);
      final tile = _tile(_main['url'] as String);
      expect(tile, findsOneWidget);
      final image = tester.widget<Image>(
        find.descendant(of: tile, matching: find.byType(Image)),
      );
      expect(image.fit, BoxFit.contain);
    });
  });

  group('2:3 cover crop', () {
    testWidgets('VNDB cover tiles use the 2:3 library ratio', (tester) async {
      await _pumpDialog(tester);
      final tile = _tile(_main['url'] as String);
      expect(tile, findsOneWidget);
      final image = find.descendant(of: tile, matching: find.byType(Image));
      expect(image, findsOneWidget);
      final size = tester.getSize(image);
      expect(size.width / size.height, closeTo(2 / 3, 0.01));
    });

    testWidgets('the library preview uses the 2:3 cover ratio', (tester) async {
      await _pumpDialog(tester);
      final previews = [
        for (final element in tester.elementList(find.byType(AspectRatio)))
          tester.getSize(find.byWidget(element.widget)),
      ].where((size) => (size.width - 220).abs() < 0.5);
      expect(previews, hasLength(1));
      final size = previews.single;
      expect(size.width / size.height, closeTo(2 / 3, 0.01));
    });

    testWidgets('the cover hint names the 2:3 crop', (tester) async {
      await _pumpDialog(tester);
      expect(
        find.text('Covers are cropped to 2:3 in the grid.'),
        findsOneWidget,
      );
    });

    testWidgets('the size caption sits below the image inside the tile', (
      tester,
    ) async {
      await _pumpDialog(tester);
      final tile = _tile(_main['url'] as String);
      expect(tile, findsOneWidget);
      expect(find.text('411×560'), findsOneWidget);
      final tileRect = tester.getRect(tile);
      final imageRect = tester.getRect(
        find.descendant(of: tile, matching: find.byType(AspectRatio)),
      );
      final textRect = tester.getRect(
        find.descendant(
          of: tile,
          matching: find.byWidgetPredicate(
            (w) => w is RichText && w.text.toPlainText() == '411×560',
          ),
        ),
      );
      expect(imageRect.width / imageRect.height, closeTo(2 / 3, 0.01));
      expect(textRect.top, greaterThanOrEqualTo(imageRect.bottom - 0.5));
      expect(textRect.left, greaterThanOrEqualTo(tileRect.left - 0.5));
      expect(textRect.right, lessThanOrEqualTo(tileRect.right + 0.5));
      expect(textRect.top, greaterThanOrEqualTo(tileRect.top - 0.5));
      expect(textRect.bottom, lessThanOrEqualTo(tileRect.bottom + 0.5));
    });
  });
}
