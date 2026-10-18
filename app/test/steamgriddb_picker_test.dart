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
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumige/src/core/covers.dart' as core;
import 'package:tsumige/src/core/model.dart' as core;
import 'package:tsumige/src/core/paths.dart' as core;
import 'package:tsumige/src/core/vndb.dart' as core;
import 'package:tsumige/src/features/library/data/library_repository.dart';
import 'package:tsumige/src/features/library/domain/add_game.dart';
import 'package:tsumige/src/features/library/presentation/widgets/art_picker_dialog.dart';
import 'package:tsumige/src/features/library/presentation/widgets/detail_tabs/related_tab.dart';
import 'package:tsumige/src/utils/prefs/app_prefs.dart';
import 'package:tsumige/src/utils/prefs/prefs_mixin.dart';
import 'package:tsumige/src/utils/theme/brand.dart';
import 'package:tsumige/src/widgets/tsumige_logo.dart';

const _sgdbCover = 'https://example.com/sgdb-cover.jpg';
const _sgdbHero = 'https://example.com/sgdb-hero.jpg';

String _gridsBody(List<String> urls) => jsonEncode({
  'success': true,
  'data': [
    for (var i = 0; i < urls.length; i++)
      {
        'id': i + 1,
        'width': 600,
        'height': 900,
        'url': urls[i],
        'thumb': '${urls[i]}-thumb',
      },
  ],
});

String _heroesBody(List<String> urls) => jsonEncode({
  'success': true,
  'data': [
    for (var i = 0; i < urls.length; i++)
      {
        'id': i + 1,
        'width': 1920,
        'height': 620,
        'url': urls[i],
        'thumb': '${urls[i]}-thumb',
      },
  ],
});

class _SgdbConfig {
  _SgdbConfig({
    this.gridsStatus = 200,
    this.gridsUrls = const [_sgdbCover],
    this.heroesStatus = 200,
    this.heroesUrls = const [_sgdbHero],
    this.searchNames = const <String>[],
    this.searchStatus = 200,
    this.hangGrids = false,
    this.hangHeroes = false,
    this.releaseGate,
    this.searchGate,
    this.vndbExtlinks = const <Map<String, Object?>>[],
    this.sgdbRequests,
    this.vndbReleaseBodies,
    this.vndbReleaseStatus = 200,
    this.gridGates = const {},
    this.heroGates = const {},
  });

  int gridsStatus;
  List<String> gridsUrls;
  int heroesStatus;
  List<String> heroesUrls;
  List<String> searchNames;
  int searchStatus;
  bool hangGrids;
  bool hangHeroes;
  Completer<void>? releaseGate;
  Completer<void>? searchGate;
  List<Map<String, Object?>> vndbExtlinks;
  List<Uri>? sgdbRequests;
  List<String>? vndbReleaseBodies;
  int vndbReleaseStatus;
  Map<int, Completer<http.Response>> gridGates;
  Map<int, Completer<http.Response>> heroGates;
}

http.Client _fakeSgdbHttp(_SgdbConfig config, List<String> downloads) {
  final png = Uint8List.fromList(
    img.encodePng(img.Image(width: 16, height: 16)),
  );
  return MockClient((request) async {
    final url = request.url;
    if (url.host == 'www.steamgriddb.com') {
      config.sgdbRequests?.add(url);
      if (config.hangGrids && url.path.contains('/grids/')) {
        await Completer<http.Response>().future;
        throw StateError('unreachable');
      }
      if (url.path.contains('/search/autocomplete/')) {
        if (config.searchGate != null) await config.searchGate!.future;
        if (config.searchStatus != 200) {
          return http.Response('error', config.searchStatus);
        }
        final names = config.searchNames;
        return http.Response(
          jsonEncode({
            'data': [
              for (var i = 0; i < names.length; i++)
                {'id': 10 + i, 'name': names[i]},
            ],
          }),
          200,
        );
      }
      if (url.path.contains('/heroes/')) {
        if (config.hangHeroes) {
          await Completer<http.Response>().future;
          throw StateError('unreachable');
        }
        final gate = int.tryParse(url.pathSegments.last) != null
            ? config.heroGates[int.parse(url.pathSegments.last)]
            : null;
        if (gate != null) return gate.future;
        return http.Response(
          config.heroesStatus == 200
              ? _heroesBody(config.heroesUrls)
              : 'error',
          config.heroesStatus,
        );
      }
      if (url.path.contains('/grids/')) {
        final gate = int.tryParse(url.pathSegments.last) != null
            ? config.gridGates[int.parse(url.pathSegments.last)]
            : null;
        if (gate != null) return gate.future;
        return http.Response(
          config.gridsStatus == 200
              ? _gridsBody(config.gridsUrls)
              : 'error',
          config.gridsStatus,
        );
      }
      return http.Response('not found', 404);
    }
    if (url.host == 'api.vndb.org') {
      if (url.path.endsWith('/vn')) {
        return http.Response(
          jsonEncode({
            'results': [
              {
                'image': {
                  'url': 'https://t.vndb.org/cv/16/98416.jpg',
                  'thumbnail': 'https://t.vndb.org/cv.t/16/98416.jpg',
                  'dims': [411, 560],
                },
                'screenshots': [],
              },
            ],
            'more': false,
          }),
          200,
        );
      }
      if (url.path.endsWith('/release')) {
        config.vndbReleaseBodies?.add(request.body);
        if (config.releaseGate != null) await config.releaseGate!.future;
        if (config.vndbReleaseStatus != 200) {
          return http.Response('error', config.vndbReleaseStatus);
        }
        return http.Response(
          jsonEncode({
            'results': [
              {
                'images': [],
                'extlinks': config.vndbExtlinks,
              },
            ],
            'more': false,
          }),
          200,
        );
      }
    }
    downloads.add(url.toString());
    return http.Response.bytes(
      png,
      200,
      headers: {'content-type': 'image/png'},
    );
  });
}

class _FakeRepository implements LibraryRepository {
  _FakeRepository(this.loaded);

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

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<core.LoadedLibrary> _pumpSgdbDialog(
  WidgetTester tester, {
  core.Game? game,
  _SgdbConfig? config,
  List<String>? downloads,
  String? prefsKey,
  List<Uri>? openedUris,
}) async {
  final cfg = config ?? _SgdbConfig();
  final temp = Directory.systemTemp.createTempSync('tsumige_sgdb_picker_');
  addTearDown(() => temp.deleteSync(recursive: true));
  final g = game ?? core.Game(id: 'g1', title: 'DiviDead', vndbId: 'v1');
  final loaded = core.LoadedLibrary(library: core.Library(games: [g]));
  tester.view.physicalSize = const Size(1400, 980);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  SharedPreferences.setMockInitialValues(
    prefsKey == null ? {} : {'artSources.steamGridDbKey': prefsKey},
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
        dataDirProvider.overrideWithValue(core.DataDir(temp.path)),
        libraryRepositoryProvider.overrideWithValue(_FakeRepository(loaded)),
        addGameHttpClientProvider.overrideWithValue(
          _fakeSgdbHttp(cfg, downloads ?? []),
        ),
        vndbUrlOpenerProvider.overrideWithValue((uri) async {
          openedUris?.add(uri);
          return true;
        }),
      ],
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) {
            ref.watch(libraryProvider);
            return Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: ElevatedButton(
                    onPressed: () => showArtPickerDialog(context, g),
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
  await _settle(tester);
  return loaded;
}

void main() {
  testWidgets('no key shows the note and Set API key', (tester) async {
    await _pumpSgdbDialog(tester);
    expect(find.text('SteamGridDB'), findsOneWidget);
    expect(
      find.text(
        'Covers from SteamGridDB need your own free API key. '
        'Get one in your SteamGridDB preferences.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('sgdb-set-key')), findsOneWidget);
  });

  testWidgets('entering a key stores it and shows tiles', (tester) async {
    final loaded = await _pumpSgdbDialog(
      tester,
      config: _SgdbConfig(
        vndbExtlinks: [
          {'name': 'steam', 'id': '123'},
        ],
      ),
    );
    await tester.tap(find.byKey(const Key('sgdb-set-key')));
    await tester.pump();
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.hintText == 'Paste your SteamGridDB API key' &&
            w.obscureText,
      ),
      findsOneWidget,
    );
    expect(find.text('Get a key'), findsOneWidget);
    final save = tester.widget<BrandButton>(find.byKey(const Key('sgdb-key-save')));
    expect(save.onPressed, isNull);
    await tester.enterText(
      find.byKey(const Key('sgdb-key-field')),
      'fake-test-key',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('sgdb-key-save')));
    await tester.pump();
    await _settle(tester);
    expect(
      find.byKey(ValueKey('art-$_sgdbCover')),
      findsOneWidget,
    );
    expect(loaded.library.games.single, isNotNull);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ArtPickerDialog)),
    );
    expect(container.read(steamGridDbKeyProvider), 'fake-test-key');
  });

  testWidgets('Steam-ID path shows tiles and Save stores the cover', (
    tester,
  ) async {
    final downloads = <String>[];
    final loaded = await _pumpSgdbDialog(
      tester,
      prefsKey: 'fake-test-key',
      downloads: downloads,
      config: _SgdbConfig(
        vndbExtlinks: [
          {'name': 'steam', 'id': '123'},
        ],
      ),
    );
    final game = loaded.library.games.single;
    expect(find.byKey(ValueKey('art-$_sgdbCover')), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('art-$_sgdbCover')));
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(BrandButton, 'Save'));
      await tester.pump();
      for (var i = 0; i < 200 && game.cover == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    });
    expect(game.cover, 'g1.png');
    expect(game.coverSource, _sgdbCover);
    expect(downloads, contains(_sgdbCover));
  });

  testWidgets('the user-set Steam app id wins over VNDB extlinks', (
    tester,
  ) async {
    final requests = <Uri>[];
    final game = core.Game(id: 'g1', title: 'DiviDead', vndbId: 'v1')
      ..launch.steamAppId = 456;
    await _pumpSgdbDialog(
      tester,
      game: game,
      prefsKey: 'fake-test-key',
      config: _SgdbConfig(
        sgdbRequests: requests,
        vndbExtlinks: [
          {'name': 'steam', 'id': '123'},
        ],
      ),
    );
    expect(find.byKey(ValueKey('art-$_sgdbCover')), findsOneWidget);
    expect(
      requests.where((u) => u.path.contains('/grids/steam/')).map((u) => u.path),
      ['/api/v2/grids/steam/456'],
    );
  });

  testWidgets('name search preselects the normalized exact match', (
    tester,
  ) async {
    await _pumpSgdbDialog(
      tester,
      prefsKey: 'fake-test-key',
      config: _SgdbConfig(searchNames: ['Something Else', 'Divi-Dead']),
    );
    expect(find.text('Divi-Dead'), findsOneWidget);
    expect(find.text('Something Else'), findsOneWidget);
    expect(find.text('Pick the matching game.'), findsNothing);
    await _settle(tester);
    expect(find.byKey(ValueKey('art-$_sgdbCover')), findsOneWidget);
  });

  testWidgets('without a match the user picks the game', (tester) async {
    await _pumpSgdbDialog(
      tester,
      prefsKey: 'fake-test-key',
      config: _SgdbConfig(searchNames: ['Something Else', 'Divi Dead 2']),
    );
    expect(find.text('Pick the matching game.'), findsOneWidget);
    expect(find.byKey(ValueKey('art-$_sgdbCover')), findsNothing);
    await tester.tap(find.text('Divi Dead 2'));
    await tester.pump();
    await _settle(tester);
    expect(find.text('Pick the matching game.'), findsNothing);
    expect(find.byKey(ValueKey('art-$_sgdbCover')), findsOneWidget);
  });

  testWidgets('a game with no VNDB id still searches by title', (
    tester,
  ) async {
    await _pumpSgdbDialog(
      tester,
      game: core.Game(id: 'g1', title: 'DiviDead'),
      prefsKey: 'fake-test-key',
      config: _SgdbConfig(searchNames: ['Divi-Dead']),
    );
    expect(find.text('Divi-Dead'), findsOneWidget);
    expect(find.byKey(ValueKey('art-$_sgdbCover')), findsOneWidget);
  });

  testWidgets('an empty result shows the empty message', (tester) async {
    await _pumpSgdbDialog(
      tester,
      prefsKey: 'fake-test-key',
      config: _SgdbConfig(
        vndbExtlinks: [
          {'name': 'steam', 'id': '123'},
        ],
        gridsUrls: const [],
      ),
    );
    expect(
      find.text('No SteamGridDB covers for this game.'),
      findsOneWidget,
    );
  });

  testWidgets('a bad key shows the message and Set API key', (tester) async {
    await _pumpSgdbDialog(
      tester,
      prefsKey: 'fake-test-key',
      config: _SgdbConfig(
        gridsStatus: 401,
        vndbExtlinks: [
          {'name': 'steam', 'id': '123'},
        ],
      ),
    );
    expect(
      find.text("SteamGridDB didn't accept the key."),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('sgdb-set-key')));
    await tester.pump();
    expect(find.byKey(const Key('sgdb-key-field')), findsOneWidget);
  });

  testWidgets('a network error shows the message and Try again recovers', (
    tester,
  ) async {
    final config = _SgdbConfig(
      gridsStatus: 500,
      vndbExtlinks: [
        {'name': 'steam', 'id': '123'},
      ],
    );
    await _pumpSgdbDialog(tester, prefsKey: 'fake-test-key', config: config);
    expect(find.text("Couldn't reach SteamGridDB."), findsOneWidget);
    config.gridsStatus = 200;
    await tester.tap(find.byKey(const Key('sgdb-retry')));
    await tester.pump();
    await _settle(tester);
    expect(find.text("Couldn't reach SteamGridDB."), findsNothing);
    expect(find.byKey(ValueKey('art-$_sgdbCover')), findsOneWidget);
  });

  testWidgets('clearing the key returns the picker to the no-key note', (
    tester,
  ) async {
    final loaded = await _pumpSgdbDialog(
      tester,
      prefsKey: 'fake-test-key',
      config: _SgdbConfig(
        vndbExtlinks: [
          {'name': 'steam', 'id': '123'},
        ],
      ),
    );
    expect(loaded, isNotNull);
    expect(find.byKey(ValueKey('art-$_sgdbCover')), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ArtPickerDialog)),
    );
    container.read(steamGridDbKeyProvider.notifier).set('');
    await tester.pump();
    await _settle(tester);
    expect(find.byKey(ValueKey('art-$_sgdbCover')), findsNothing);
    expect(find.byKey(const Key('sgdb-set-key')), findsOneWidget);
  });

  testWidgets('VNDB tiles render while SteamGridDB is still pending', (
    tester,
  ) async {
    await _pumpSgdbDialog(
      tester,
      prefsKey: 'fake-test-key',
      config: _SgdbConfig(
        hangGrids: true,
        vndbExtlinks: [
          {'name': 'steam', 'id': '123'},
        ],
      ),
    );
    expect(
      find.byKey(const ValueKey('art-https://t.vndb.org/cv/16/98416.jpg')),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byType(TsumigeLogoShimmer)),
      const Size(32, 32),
    );
  });

  testWidgets('a late first chip response does not clobber the second', (
    tester,
  ) async {
    const aTile = 'https://example.com/sgdb-a.jpg';
    const bTile = 'https://example.com/sgdb-b.jpg';
    final aGate = Completer<http.Response>();
    final bGate = Completer<http.Response>();
    await _pumpSgdbDialog(
      tester,
      game: core.Game(id: 'g1', title: 'DiviDead'),
      prefsKey: 'fake-test-key',
      config: _SgdbConfig(
        searchNames: ['Alpha Game', 'Beta Game'],
        gridGates: {10: aGate, 11: bGate},
      ),
    );
    expect(find.text('Pick the matching game.'), findsOneWidget);
    await tester.tap(find.text('Alpha Game'));
    await tester.pump();
    await tester.tap(find.text('Beta Game'));
    await tester.pump();
    bGate.complete(http.Response(_gridsBody([bTile]), 200));
    await tester.pump();
    await tester.pump();
    aGate.complete(http.Response(_gridsBody([aTile]), 200));
    await _settle(tester);
    expect(find.byKey(ValueKey('art-$bTile')), findsOneWidget);
    expect(find.byKey(ValueKey('art-$aTile')), findsNothing);
    expect(
      tester.widget<Text>(find.text('Beta Game')).style?.fontWeight,
      FontWeight.w600,
    );
    expect(
      tester.widget<Text>(find.text('Alpha Game')).style?.fontWeight,
      FontWeight.w400,
    );
  });

  testWidgets('a VNDB failure falls through to the name search', (
    tester,
  ) async {
    await _pumpSgdbDialog(
      tester,
      prefsKey: 'fake-test-key',
      config: _SgdbConfig(
        vndbReleaseStatus: 500,
        searchNames: ['Divi-Dead'],
      ),
    );
    expect(find.text("Couldn't reach SteamGridDB."), findsNothing);
    expect(
      find.byKey(ValueKey('art-$_sgdbCover')),
      findsOneWidget,
    );
  });

  testWidgets('canceling the key form keeps the no-key note without saving', (
    tester,
  ) async {
    await _pumpSgdbDialog(tester);
    await tester.tap(find.byKey(const Key('sgdb-set-key')));
    await tester.pump();
    expect(find.byKey(const Key('sgdb-key-field')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('sgdb-key-field')),
      'typed-but-cancelled',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('sgdb-key-cancel')));
    await tester.pump();
    expect(find.byKey(const Key('sgdb-key-field')), findsNothing);
    expect(
      find.text(
        'Covers from SteamGridDB need your own free API key. '
        'Get one in your SteamGridDB preferences.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('sgdb-set-key')), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ArtPickerDialog)),
    );
    expect(container.read(steamGridDbKeyProvider), isEmpty);
  });

  testWidgets('canceling the key form keeps the bad-key message without saving', (
    tester,
  ) async {
    await _pumpSgdbDialog(
      tester,
      prefsKey: 'fake-test-key',
      config: _SgdbConfig(
        gridsStatus: 401,
        vndbExtlinks: [
          {'name': 'steam', 'id': '123'},
        ],
      ),
    );
    expect(
      find.text("SteamGridDB didn't accept the key."),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('sgdb-set-key')));
    await tester.pump();
    expect(find.byKey(const Key('sgdb-key-field')), findsOneWidget);
    await tester.tap(find.byKey(const Key('sgdb-key-cancel')));
    await tester.pump();
    expect(find.byKey(const Key('sgdb-key-field')), findsNothing);
    expect(
      find.text("SteamGridDB didn't accept the key."),
      findsOneWidget,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ArtPickerDialog)),
    );
    expect(container.read(steamGridDbKeyProvider), 'fake-test-key');
  });

  testWidgets('Background tab shows heroes and Save stores the background', (
    tester,
  ) async {
    final downloads = <String>[];
    final loaded = await _pumpSgdbDialog(
      tester,
      prefsKey: 'fake-test-key',
      downloads: downloads,
      config: _SgdbConfig(
        vndbExtlinks: [
          {'name': 'steam', 'id': '123'},
        ],
      ),
    );
    final game = loaded.library.games.single;
    expect(find.byKey(ValueKey('art-$_sgdbCover')), findsOneWidget);
    await tester.tap(find.text('Background'));
    await tester.pump();
    await _settle(tester);
    expect(find.text('SteamGridDB'), findsOneWidget);
    expect(find.byKey(ValueKey('art-$_sgdbHero')), findsOneWidget);
    expect(find.byKey(ValueKey('art-$_sgdbCover')), findsNothing);
    await tester.tap(find.byKey(ValueKey('art-$_sgdbHero')));
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(BrandButton, 'Save'));
      await tester.pump();
      for (var i = 0; i < 200 && game.background == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    });
    expect(game.background, 'g1.png');
    expect(game.backgroundSource, _sgdbHero);
    expect(downloads, contains(_sgdbHero));
  });

  testWidgets('Cover, Background, Cover fetches each source once', (
    tester,
  ) async {
    final sgdb = <Uri>[];
    final releaseBodies = <String>[];
    await _pumpSgdbDialog(
      tester,
      prefsKey: 'fake-test-key',
      config: _SgdbConfig(
        sgdbRequests: sgdb,
        vndbReleaseBodies: releaseBodies,
        vndbExtlinks: [
          {'name': 'steam', 'id': '123'},
        ],
      ),
    );
    expect(find.byKey(ValueKey('art-$_sgdbCover')), findsOneWidget);
    await tester.tap(find.text('Background'));
    await tester.pump();
    await _settle(tester);
    expect(find.byKey(ValueKey('art-$_sgdbHero')), findsOneWidget);
    await tester.tap(find.text('Cover'));
    await tester.pump();
    await _settle(tester);
    expect(find.byKey(ValueKey('art-$_sgdbCover')), findsOneWidget);
    expect(
      releaseBodies.where((b) => b.contains('"extlink"')),
      hasLength(1),
    );
    expect(
      sgdb.where((u) => u.path == '/api/v2/grids/steam/123'),
      hasLength(1),
    );
    expect(
      sgdb.where((u) => u.path == '/api/v2/heroes/steam/123'),
      hasLength(1),
    );
    expect(
      sgdb.where((u) => u.path.contains('/search/autocomplete/')),
      isEmpty,
    );
  });

  testWidgets('a search chip picked on Cover is shared with Background', (
    tester,
  ) async {
    final sgdb = <Uri>[];
    await _pumpSgdbDialog(
      tester,
      prefsKey: 'fake-test-key',
      config: _SgdbConfig(
        sgdbRequests: sgdb,
        searchNames: ['Something Else', 'Divi Dead 2'],
      ),
    );
    expect(find.text('Pick the matching game.'), findsOneWidget);
    await tester.tap(find.text('Divi Dead 2'));
    await tester.pump();
    await _settle(tester);
    expect(find.text('Pick the matching game.'), findsNothing);
    expect(find.byKey(ValueKey('art-$_sgdbCover')), findsOneWidget);
    await tester.tap(find.text('Background'));
    await tester.pump();
    await _settle(tester);
    expect(
      tester.widget<Text>(find.text('Divi Dead 2')).style?.fontWeight,
      FontWeight.w600,
    );
    expect(find.text('Pick the matching game.'), findsNothing);
    expect(find.byKey(ValueKey('art-$_sgdbHero')), findsOneWidget);
    expect(
      sgdb.where((u) => u.path.contains('/search/autocomplete/')),
      hasLength(1),
    );
    expect(
      sgdb.where((u) => u.path == '/api/v2/grids/game/11'),
      hasLength(1),
    );
    expect(
      sgdb.where((u) => u.path == '/api/v2/heroes/game/11'),
      hasLength(1),
    );
  });

  testWidgets('Background without a key shows the background wording', (
    tester,
  ) async {
    await _pumpSgdbDialog(tester);
    await tester.tap(find.text('Background'));
    await tester.pump();
    await _settle(tester);
    expect(
      find.text(
        'Backgrounds from SteamGridDB need your own free API key. '
        'Get one in your SteamGridDB preferences.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('sgdb-set-key')), findsOneWidget);
  });

  testWidgets('empty heroes show the background empty message', (
    tester,
  ) async {
    await _pumpSgdbDialog(
      tester,
      prefsKey: 'fake-test-key',
      config: _SgdbConfig(
        vndbExtlinks: [
          {'name': 'steam', 'id': '123'},
        ],
        heroesUrls: const [],
      ),
    );
    await tester.tap(find.text('Background'));
    await tester.pump();
    await _settle(tester);
    expect(
      find.text('No SteamGridDB backgrounds for this game.'),
      findsOneWidget,
    );
  });

  testWidgets('a heroes error shows Try again and recovers', (tester) async {
    final config = _SgdbConfig(
      heroesStatus: 500,
      vndbExtlinks: [
        {'name': 'steam', 'id': '123'},
      ],
    );
    await _pumpSgdbDialog(tester, prefsKey: 'fake-test-key', config: config);
    await tester.tap(find.text('Background'));
    await tester.pump();
    await _settle(tester);
    expect(find.text("Couldn't reach SteamGridDB."), findsOneWidget);
    config.heroesStatus = 200;
    await tester.tap(find.byKey(const Key('sgdb-retry')));
    await tester.pump();
    await _settle(tester);
    expect(find.text("Couldn't reach SteamGridDB."), findsNothing);
    expect(find.byKey(ValueKey('art-$_sgdbHero')), findsOneWidget);
  });

  testWidgets('VNDB artwork renders while heroes are still pending', (
    tester,
  ) async {
    await _pumpSgdbDialog(
      tester,
      prefsKey: 'fake-test-key',
      config: _SgdbConfig(
        hangHeroes: true,
        vndbExtlinks: [
          {'name': 'steam', 'id': '123'},
        ],
      ),
    );
    await tester.tap(find.text('Background'));
    await tester.pump();
    await _settle(tester);
    expect(
      find.byKey(const ValueKey('art-https://t.vndb.org/cv/16/98416.jpg')),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byType(TsumigeLogoShimmer)),
      const Size(32, 32),
    );
  });

  testWidgets('a late first hero response does not clobber the second', (
    tester,
  ) async {
    const aTile = 'https://example.com/sgdb-hero-a.jpg';
    const bTile = 'https://example.com/sgdb-hero-b.jpg';
    final aGate = Completer<http.Response>();
    final bGate = Completer<http.Response>();
    await _pumpSgdbDialog(
      tester,
      game: core.Game(id: 'g1', title: 'DiviDead'),
      prefsKey: 'fake-test-key',
      config: _SgdbConfig(
        searchNames: ['Alpha Game', 'Beta Game'],
        heroGates: {10: aGate, 11: bGate},
      ),
    );
    await tester.tap(find.text('Background'));
    await tester.pump();
    await _settle(tester);
    expect(find.text('Pick the matching game.'), findsOneWidget);
    await tester.tap(find.text('Alpha Game'));
    await tester.pump();
    await tester.tap(find.text('Beta Game'));
    await tester.pump();
    bGate.complete(http.Response(_heroesBody([bTile]), 200));
    await tester.pump();
    await tester.pump();
    aGate.complete(http.Response(_heroesBody([aTile]), 200));
    await _settle(tester);
    expect(find.byKey(ValueKey('art-$bTile')), findsOneWidget);
    expect(find.byKey(ValueKey('art-$aTile')), findsNothing);
    expect(
      tester.widget<Text>(find.text('Beta Game')).style?.fontWeight,
      FontWeight.w600,
    );
    expect(
      tester.widget<Text>(find.text('Alpha Game')).style?.fontWeight,
      FontWeight.w400,
    );
  });

  testWidgets('switching tabs during the Steam ID lookup runs it once', (
    tester,
  ) async {
    final releaseGate = Completer<void>();
    final sgdb = <Uri>[];
    final releaseBodies = <String>[];
    await _pumpSgdbDialog(
      tester,
      prefsKey: 'fake-test-key',
      config: _SgdbConfig(
        sgdbRequests: sgdb,
        vndbReleaseBodies: releaseBodies,
        vndbExtlinks: [
          {'name': 'steam', 'id': '123'},
        ],
        releaseGate: releaseGate,
      ),
    );
    expect(find.byKey(ValueKey('art-$_sgdbCover')), findsNothing);
    await tester.tap(find.text('Background'));
    await tester.pump();
    await tester.pump();
    expect(
      releaseBodies.where((b) => b.contains('"extlink"')),
      hasLength(1),
    );
    releaseGate.complete();
    await _settle(tester);
    expect(find.byKey(ValueKey('art-$_sgdbHero')), findsOneWidget);
    await tester.tap(find.text('Cover'));
    await tester.pump();
    await _settle(tester);
    expect(find.byKey(ValueKey('art-$_sgdbCover')), findsOneWidget);
    expect(
      releaseBodies.where((b) => b.contains('"extlink"')),
      hasLength(1),
    );
    expect(
      sgdb.where((u) => u.path == '/api/v2/grids/steam/123'),
      hasLength(1),
    );
    expect(
      sgdb.where((u) => u.path == '/api/v2/heroes/steam/123'),
      hasLength(1),
    );
  });

  testWidgets('switching tabs during the name search runs it once', (
    tester,
  ) async {
    final searchGate = Completer<void>();
    final sgdb = <Uri>[];
    await _pumpSgdbDialog(
      tester,
      prefsKey: 'fake-test-key',
      config: _SgdbConfig(
        sgdbRequests: sgdb,
        searchNames: ['Divi-Dead'],
        searchGate: searchGate,
      ),
    );
    expect(find.byKey(ValueKey('art-$_sgdbCover')), findsNothing);
    await tester.tap(find.text('Background'));
    await tester.pump();
    await tester.pump();
    expect(
      sgdb.where((u) => u.path.contains('/search/autocomplete/')),
      hasLength(1),
    );
    searchGate.complete();
    await _settle(tester);
    expect(find.byKey(ValueKey('art-$_sgdbHero')), findsOneWidget);
    await tester.tap(find.text('Cover'));
    await tester.pump();
    await _settle(tester);
    expect(find.byKey(ValueKey('art-$_sgdbCover')), findsOneWidget);
    expect(
      sgdb.where((u) => u.path.contains('/search/autocomplete/')),
      hasLength(1),
    );
    expect(
      sgdb.where((u) => u.path == '/api/v2/grids/game/10'),
      hasLength(1),
    );
    expect(
      sgdb.where((u) => u.path == '/api/v2/heroes/game/10'),
      hasLength(1),
    );
  });

  testWidgets('switching tabs during a grids fetch joins it', (tester) async {
    final gridsGate = Completer<http.Response>();
    final sgdb = <Uri>[];
    await _pumpSgdbDialog(
      tester,
      prefsKey: 'fake-test-key',
      config: _SgdbConfig(
        sgdbRequests: sgdb,
        vndbExtlinks: [
          {'name': 'steam', 'id': '123'},
        ],
        gridGates: {123: gridsGate},
      ),
    );
    expect(find.byKey(ValueKey('art-$_sgdbCover')), findsNothing);
    await tester.tap(find.text('Background'));
    await tester.pump();
    await _settle(tester);
    expect(find.byKey(ValueKey('art-$_sgdbHero')), findsOneWidget);
    await tester.tap(find.text('Cover'));
    await tester.pump();
    await tester.pump();
    expect(
      sgdb.where((u) => u.path == '/api/v2/grids/steam/123'),
      hasLength(1),
    );
    expect(
      sgdb.where((u) => u.path == '/api/v2/heroes/steam/123'),
      hasLength(1),
    );
    gridsGate.complete(http.Response(_gridsBody([_sgdbCover]), 200));
    await _settle(tester);
    expect(find.byKey(ValueKey('art-$_sgdbCover')), findsOneWidget);
    await tester.tap(find.text('Background'));
    await tester.pump();
    await _settle(tester);
    expect(find.byKey(ValueKey('art-$_sgdbHero')), findsOneWidget);
  });

  testWidgets('Try again after an art error keeps the picked game', (
    tester,
  ) async {
    final sgdb = <Uri>[];
    final config = _SgdbConfig(
      sgdbRequests: sgdb,
      gridsStatus: 500,
      searchNames: ['Something Else', 'Divi Dead 2'],
    );
    await _pumpSgdbDialog(tester, prefsKey: 'fake-test-key', config: config);
    expect(find.text('Pick the matching game.'), findsOneWidget);
    await tester.tap(find.text('Divi Dead 2'));
    await tester.pump();
    await _settle(tester);
    expect(find.text("Couldn't reach SteamGridDB."), findsOneWidget);
    config.gridsStatus = 200;
    await tester.tap(find.byKey(const Key('sgdb-retry')));
    await tester.pump();
    await _settle(tester);
    expect(find.text("Couldn't reach SteamGridDB."), findsNothing);
    expect(find.byKey(ValueKey('art-$_sgdbCover')), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('Divi Dead 2')).style?.fontWeight,
      FontWeight.w600,
    );
    expect(
      sgdb.where((u) => u.path.contains('/search/autocomplete/')),
      hasLength(1),
    );
    expect(
      sgdb.where((u) => u.path == '/api/v2/grids/game/11'),
      hasLength(2),
    );
  });

  testWidgets('canceling the key form then switching tabs runs one lookup', (
    tester,
  ) async {
    final searchGate = Completer<void>();
    final sgdb = <Uri>[];
    final releaseBodies = <String>[];
    final config = _SgdbConfig(
      sgdbRequests: sgdb,
      vndbReleaseBodies: releaseBodies,
      searchNames: ['Divi-Dead'],
      searchStatus: 401,
    );
    await _pumpSgdbDialog(tester, prefsKey: 'fake-test-key', config: config);
    expect(
      find.text("SteamGridDB didn't accept the key."),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('sgdb-set-key')));
    await tester.pump();
    expect(find.byKey(const Key('sgdb-key-field')), findsOneWidget);
    config.searchGate = searchGate;
    config.searchStatus = 200;
    await tester.tap(find.byKey(const Key('sgdb-key-cancel')));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Background'));
    await tester.pump();
    await tester.pump();
    expect(
      releaseBodies.where((b) => b.contains('"extlink"')),
      hasLength(2),
    );
    expect(
      sgdb.where((u) => u.path.contains('/search/autocomplete/')),
      hasLength(2),
    );
    searchGate.complete();
    await _settle(tester);
    expect(find.byKey(ValueKey('art-$_sgdbHero')), findsOneWidget);
    await tester.tap(find.text('Cover'));
    await tester.pump();
    await _settle(tester);
    expect(find.byKey(ValueKey('art-$_sgdbCover')), findsOneWidget);
    expect(
      releaseBodies.where((b) => b.contains('"extlink"')),
      hasLength(2),
    );
    expect(
      sgdb.where((u) => u.path.contains('/search/autocomplete/')),
      hasLength(2),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ArtPickerDialog)),
    );
    expect(container.read(steamGridDbKeyProvider), 'fake-test-key');
  });
}
