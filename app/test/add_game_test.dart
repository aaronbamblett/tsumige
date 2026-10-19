// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluttertoast/fluttertoast.dart';
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
import 'package:tsumige/src/core/host_platform.dart';
import 'package:tsumige/src/features/library/data/library_repository.dart';
import 'package:tsumige/src/features/library/domain/add_game.dart';
import 'package:tsumige/src/features/library/domain/folder_import.dart';
import 'package:tsumige/src/features/library/domain/game_editor.dart';
import 'package:tsumige/src/features/library/domain/selection.dart';
import 'package:tsumige/src/features/library/domain/steam_library.dart';
import 'package:tsumige/src/features/library/presentation/add_game/add_game_dialog.dart';
import 'package:tsumige/src/features/library/presentation/add_game/import_folder_dialog.dart';
import 'package:tsumige/src/features/library/presentation/widgets/detail_tabs/info_tab.dart';
import 'package:tsumige/src/features/settings/presentation/sections/settings_widgets.dart';
import 'package:tsumige/src/utils/prefs/prefs_mixin.dart';
import 'package:tsumige/src/utils/theme/brand.dart';

class _FakeRepository implements LibraryRepository {
  _FakeRepository(this.games);

  final List<core.Game> games;
  int saves = 0;
  Completer<void>? saveGate;

  @override
  Future<core.LoadedLibrary> load() async =>
      core.LoadedLibrary(library: core.Library(games: games));

  @override
  Future<void> save(core.LoadedLibrary loaded) async {
    await saveGate?.future;
    saves++;
  }

  @override
  Future<core.VndbRefreshReport> refreshVndbData(
    core.LoadedLibrary loaded,
  ) async => const core.VndbRefreshReport();

  @override
  Future<core.ThumbReport> ensureThumbnails(core.Library library) async =>
      core.ThumbReport();
}

class _Http {
  _Http({required this.rows});

  final List<Map<String, Object?>> rows;
  int posts = 0;
  int gets = 0;
  bool failSearch = false;
  bool failMetadata = false;
  List<Map<String, Object?>> metadataRows = const [];
  List<Map<String, Object?>> releaseRows = const [];
  Uint8List? coverBytes;

  MockClient get client => MockClient((request) async {
    if (request.method == 'POST') {
      posts++;
      if (failSearch) return http.Response('boom', 500);
      if (request.url.path.endsWith('/release')) {
        return http.Response(
          jsonEncode({'results': releaseRows, 'more': false}),
          200,
        );
      }
      final fields = (jsonDecode(request.body) as Map)['fields'] as String;
      if (fields.contains('length_minutes')) {
        if (failMetadata) return http.Response('boom', 500);
        return http.Response.bytes(
          utf8.encode(jsonEncode({'results': metadataRows, 'more': false})),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response(jsonEncode({'results': rows, 'more': false}), 200);
    }
    gets++;
    final bytes = coverBytes;
    if (bytes == null) return http.Response('missing', 404);
    return http.Response.bytes(bytes, 200);
  });
}

Map<String, Object?> _row(
  String id,
  String title, {
  String? alttitle,
  String released = '2020-06-19',
  double? rating = 85.0,
  int votecount = 42,
  String? imageUrl,
  String description = 'A story.',
  List<String> developers = const ['Sample Studio'],
  List<String> tags = const ['Romance', 'Drama'],
}) {
  return {
    'id': id,
    'title': title,
    if (alttitle case final alt) 'alttitle': alt,
    'titles': [],
    'released': released,
    if (rating case final rat) 'rating': rat,
    'votecount': votecount,
    if (imageUrl case final url) 'image': {'url': url, 'sexual': 0},
    'description': description,
    'developers': [
      for (final d in developers) {'name': d},
    ],
    'tags': [
      for (final t in tags) {'name': t, 'rating': 80.0, 'spoiler': 0},
    ],
  };
}

Uint8List _png() => img.encodePng(img.Image(width: 8, height: 8));

Future<(_FakeRepository, _Http, ProviderContainer)> _pump(
  WidgetTester tester, {
  List<core.Game> games = const [],
  List<Map<String, Object?>> rows = const [],
  Size surface = const Size(1280, 800),
  bool openMatch = true,
  String Function(String folder)? pickFolder,
  FolderGameCount? countGames,
  PlatformException? pickError,
  Future<List<InstalledSteamGame>?> Function(HostPlatform)? steamGames,
}) async {
  tester.view.physicalSize = surface;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final temp = Directory.systemTemp.createTempSync('tsumige_add_game_test_');
  addTearDown(() => temp.deleteSync(recursive: true));
  final folder = _gameFolder(temp);
  final exe = p.join(folder, 'DEMO.exe');
  SharedPreferences.setMockInitialValues({});
  final fake = _FakeRepository([...games]);
  final http = _Http(rows: rows);
  late ProviderContainer container;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
        dataDirProvider.overrideWithValue(core.DataDir(temp.path)),
        libraryRepositoryProvider.overrideWithValue(fake),
        addGameHttpClientProvider.overrideWithValue(http.client),
        folderGameCountProvider.overrideWithValue(
          countGames ?? countImportGames,
        ),
        if (steamGames != null)
          listSteamGamesProvider.overrideWithValue(steamGames),
        pathPickerProvider.overrideWithValue(
          ({String? initialDirectory, PathPickMode? mode}) async {
            if (pickError != null) throw pickError;
            return mode == PathPickMode.file
                ? exe
                : (pickFolder?.call(folder) ?? folder);
          },
        ),
      ],
      child: MaterialApp(
        builder: FToastBuilder(),
        home: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return Scaffold(
              body: TextButton(
                onPressed: () => showAddGameDialog(context),
                child: const Text('open'),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  expect(find.text('Choose folder…'), findsOneWidget);
  if (openMatch) await _chooseFolder(tester);
  return (fake, http, container);
}

/// The game folder used by the harness: a DEMO folder with DEMO.exe.
String _gameFolder(Directory temp) {
  final folder = Directory(p.join(temp.path, 'DEMO'))..createSync();
  File(p.join(folder.path, 'DEMO.exe')).writeAsBytesSync([0, 1, 2]);
  return folder.path;
}

/// Chooses the harness folder or file from the start step and waits for the
/// match step.
Future<void> _chooseFolder(
  WidgetTester tester, {
  String key = 'add-game-choose-folder',
}) async {
  await tester.tap(find.byKey(Key(key)));
  for (
    var i = 0;
    i < 100 && find.text('Match on VNDB').evaluate().isEmpty;
    i++
  ) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

/// Moves from the match step to the setup step with the selected result.
Future<void> _next(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('add-game-next')));
  await tester.pumpAndSettle();
}

Future<void> _search(WidgetTester tester, String query, _Http http) async {
  await tester.enterText(find.byKey(const Key('add-game-search')), query);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
  await tester.pump();
}

// find.text also matches the search field's editable text, so row taps must
// be scoped to the result list.
Finder _resultRow(String title) =>
    find.descendant(of: find.byType(ListView), matching: find.text(title));

// The cover pipeline runs on isolates, which pumpAndSettle does not wait for.
// Poll in real time until the save lands, then settle and drain toast timers.
Future<void> _waitForSave(WidgetTester tester, _FakeRepository fake) async {
  for (var i = 0; i < 200 && fake.saves == 0; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

// FToast dismisses on a 3-second timer that outlives pumpAndSettle, so drain
// it after the toast assertions or teardown fails on a pending timer.
Future<void> _drainToast(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 6));

void main() {
  testWidgets('choosing a folder shows Checking folder while the probe runs', (
    tester,
  ) async {
    final gate = Completer<int>();
    final probed = <String>[];
    await _pump(
      tester,
      openMatch: false,
      countGames: (path, platform) {
        probed.add(path);
        return gate.future;
      },
    );
    await tester.tap(find.byKey(const Key('add-game-choose-folder')));
    await tester.pump();
    expect(find.text('Checking folder…'), findsOneWidget);
    // Further picks are ignored until the probe resolves.
    await tester.tap(find.byKey(const Key('add-game-choose-folder')));
    await tester.pump();
    expect(probed, hasLength(1));
    expect(find.text('Checking folder…'), findsOneWidget);
    gate.complete(1);
    for (
      var i = 0;
      i < 100 && find.text('Match on VNDB').evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('Match on VNDB'), findsOneWidget);
    expect(find.text('Checking folder…'), findsNothing);
  });

  testWidgets('typing searches once after the debounce', (tester) async {
    final (_, http, _) = await _pump(
      tester,
      rows: [_row('v900017', 'DEMO', imageUrl: null)],
    );
    await tester.pumpAndSettle();
    final before = http.posts;
    await tester.enterText(find.byKey(const Key('add-game-search')), 'DEMO 2');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 399));
    expect(http.posts, before);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    await tester.pump();
    expect(http.posts, before + 1);
    expect(find.text('DEMO'), findsWidgets);
  });

  testWidgets('results render with metadata', (tester) async {
    final (_, http, _) = await _pump(
      tester,
      rows: [
        _row('v900017', 'DEMO', alttitle: 'Demo', imageUrl: null),
        _row(
          'v1',
          'Unrated Game',
          imageUrl: null,
          rating: null,
          released: '2019-03-01',
          developers: ['Other Dev'],
        ),
      ],
    );
    await _search(tester, 'DEMO', http);
    expect(find.text('DEMO'), findsWidgets);
    expect(find.text('Unrated Game'), findsOneWidget);
    expect(find.text('Demo'), findsWidgets);
    expect(find.textContaining('2020'), findsWidgets);
    expect(find.textContaining('Sample Studio'), findsWidgets);
    expect(find.text('★ 8.5'), findsWidgets);
  });

  testWidgets('an In library result warns but can be picked', (tester) async {
    final (_, http, _) = await _pump(
      tester,
      games: [core.Game(id: 'g1', title: 'Owned', vndbId: 'v900017')],
      rows: [
        _row('v900017', 'DEMO', imageUrl: null),
        _row('v1', 'Other Game', imageUrl: null),
      ],
    );
    await _search(tester, 'DEMO', http);
    expect(find.text('In library'), findsOneWidget);
    await tester.tap(_resultRow('DEMO'));
    await tester.pumpAndSettle();
    await _next(tester);
    expect(find.text('Details'), findsOneWidget);
  });

  testWidgets('picking moves to step 2 with the fields filled', (tester) async {
    final (_, http, _) = await _pump(
      tester,
      rows: [
        _row(
          'v900017',
          'DEMO',
          imageUrl: null,
          description: 'A story.',
          tags: ['Romance'],
        ),
      ],
    );
    await _search(tester, 'DEMO', http);
    await tester.tap(_resultRow('DEMO'));
    await tester.pumpAndSettle();
    await _next(tester);
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(const Key('add-game-title')),
              matching: find.byType(TextField),
            ),
          )
          .controller!
          .text,
      'DEMO',
    );
    expect(find.byKey(const Key('add-game-description')), findsNothing);
    expect(
      find.text(
        'Description, VNDB tags and art come from VNDB. Launch '
        'settings can be changed later in the Launch tab.',
      ),
      findsNothing,
    );
    expect(find.byType(TagChip), findsNothing);
    expect(find.text('Romance'), findsNothing);
    expect(find.widgetWithText(BrandButton, 'Add'), findsOneWidget);
    expect(find.widgetWithText(BrandGlassButton, 'Back'), findsOneWidget);
  });

  testWidgets('a VNDB pick starts with empty own tags', (tester) async {
    final (_, http, _) = await _pump(
      tester,
      rows: [
        _row(
          'v900017',
          'DEMO',
          imageUrl: null,
          tags: ['Romance', 'Drama'],
        ),
      ],
    );
    await _search(tester, 'DEMO', http);
    await tester.tap(_resultRow('DEMO'));
    await tester.pumpAndSettle();
    await _next(tester);
    expect(find.byType(TagChip), findsNothing);
    expect(find.text('Romance'), findsNothing);
    expect(find.text('Drama'), findsNothing);
  });

  testWidgets('adding from VNDB leaves own tags empty but fills vndbTags', (
    tester,
  ) async {
    final (fake, http, _) = await _pump(
      tester,
      rows: [
        _row(
          'v900017',
          'DEMO',
          imageUrl: null,
          tags: ['Romance', 'Drama'],
        ),
      ],
    );
    http.metadataRows = [
      {
        'id': 'v900017',
        'alttitle': 'デモ',
        'length_minutes': 1200,
        'length_votes': 88,
        'olang': 'ja',
        'developers': [
          {'id': 'p1', 'name': 'Sample Studio'},
        ],
        'tags': [
          {'name': 'Romance', 'rating': 2.5, 'spoiler': 0, 'category': 'cont'},
        ],
        'relations': [],
      },
    ];
    http.releaseRows = [
      {
        'vns': [
          {'id': 'v900017'},
        ],
      },
    ];
    await _search(tester, 'DEMO', http);
    await tester.tap(_resultRow('DEMO'));
    await tester.pumpAndSettle();
    await _next(tester);
    await tester.enterText(
      find.byKey(const Key('add-game-exe')),
      '/games/demo/run.exe',
    );
    await tester.tap(find.byKey(const Key('add-game-add')));
    await _waitForSave(tester, fake);
    expect(fake.saves, 1);
    final game = fake.games.single;
    expect(game.tags, isEmpty);
    expect(game.vndbTags.single.name, 'Romance');
    expect(find.text('Added DEMO'), findsOneWidget);
    await _drainToast(tester);
  });

  testWidgets('Add with no exe and a non-Steam mode needs an executable', (
    tester,
  ) async {
    final (_, http, _) = await _pump(
      tester,
      rows: [_row('v900017', 'DEMO', imageUrl: null)],
    );
    await _search(tester, 'DEMO', http);
    await tester.tap(_resultRow('DEMO'));
    await tester.pumpAndSettle();
    await _next(tester);
    await tester.enterText(find.byKey(const Key('add-game-exe')), '');
    await tester.tap(find.byKey(const Key('add-game-add')));
    await tester.pumpAndSettle();
    expect(find.text('Pick the game file'), findsNWidgets(2));
  });

  testWidgets('Add saves through the repository and selects the game', (
    tester,
  ) async {
    final (fake, http, container) = await _pump(
      tester,
      rows: [
        _row(
          'v900017',
          'DEMO',
          imageUrl: 'http://127.0.0.1:9/cover.jpg',
          tags: ['Romance'],
        ),
      ],
    );
    http.coverBytes = _png();
    await _search(tester, 'DEMO', http);
    await tester.tap(_resultRow('DEMO'));
    await tester.pumpAndSettle();
    await _next(tester);
    await tester.enterText(
      find.byKey(const Key('add-game-exe')),
      '/games/demo/run.exe',
    );
    await tester.tap(find.byKey(const Key('add-game-add')));
    await _waitForSave(tester, fake);
    expect(fake.saves, 1);
    final game = fake.games.single;
    expect(game.title, 'DEMO');
    expect(game.vndbId, 'v900017');
    expect(game.launch.mode, core.LaunchMode.proton);
    expect(game.launch.executable, '/games/demo/run.exe');
    expect(game.cover, isNotNull);
    expect(container.read(selectedGameIdProvider), game.id);
    expect(find.text('Added DEMO'), findsOneWidget);
    await _drainToast(tester);
  });

  testWidgets('Add fills the VNDB metadata before saving', (tester) async {
    final (fake, http, _) = await _pump(
      tester,
      rows: [_row('v900017', 'DEMO', imageUrl: null)],
    );
    http.metadataRows = [
      {
        'id': 'v900017',
        'alttitle': 'デモ',
        'length_minutes': 1200,
        'length_votes': 88,
        'olang': 'ja',
        'developers': [
          {'id': 'p1', 'name': 'Sample Studio'},
        ],
        'tags': [
          {'name': 'Romance', 'rating': 2.5, 'spoiler': 0, 'category': 'cont'},
        ],
        'relations': [],
      },
    ];
    http.releaseRows = [
      {
        'vns': [
          {'id': 'v900017'},
        ],
      },
    ];
    await _search(tester, 'DEMO', http);
    await tester.tap(_resultRow('DEMO'));
    await tester.pumpAndSettle();
    await _next(tester);
    await tester.enterText(
      find.byKey(const Key('add-game-exe')),
      '/games/demo/run.exe',
    );
    await tester.tap(find.byKey(const Key('add-game-add')));
    await _waitForSave(tester, fake);
    expect(fake.saves, 1);
    final game = fake.games.single;
    expect(game.tags, isEmpty);
    expect(game.vndbOriginalTitle, 'デモ');
    expect(game.lengthMinutes, 1200);
    expect(game.originalLanguage, 'ja');
    expect(game.developers.single.name, 'Sample Studio');
    expect(game.vndbTags.single.name, 'Romance');
    expect(game.adultVndb, isTrue);
    expect(find.text('Added DEMO'), findsOneWidget);
    await _drainToast(tester);
  });

  testWidgets('a VNDB metadata failure still adds the game', (tester) async {
    final (fake, http, _) = await _pump(
      tester,
      rows: [_row('v900017', 'DEMO', imageUrl: null)],
    );
    http.failMetadata = true;
    await _search(tester, 'DEMO', http);
    await tester.tap(_resultRow('DEMO'));
    await tester.pumpAndSettle();
    await _next(tester);
    await tester.enterText(
      find.byKey(const Key('add-game-exe')),
      '/games/demo/run.exe',
    );
    await tester.tap(find.byKey(const Key('add-game-add')));
    await _waitForSave(tester, fake);
    expect(fake.saves, 1);
    final game = fake.games.single;
    expect(game.title, 'DEMO');
    expect(game.vndbId, 'v900017');
    expect(game.vndbOriginalTitle, isNull);
    expect(game.adultVndb, isNull);
    expect(find.text('Added DEMO'), findsOneWidget);
    await _drainToast(tester);
  });

  testWidgets('a cover download failure still adds the game', (tester) async {
    final (fake, http, _) = await _pump(
      tester,
      rows: [_row('v900017', 'DEMO', imageUrl: 'http://127.0.0.1:9/cover.jpg')],
    );
    await _search(tester, 'DEMO', http);
    await tester.tap(_resultRow('DEMO'));
    await tester.pumpAndSettle();
    await _next(tester);
    await tester.enterText(
      find.byKey(const Key('add-game-exe')),
      '/games/demo/run.exe',
    );
    await tester.tap(find.byKey(const Key('add-game-add')));
    await tester.pumpAndSettle();
    expect(fake.saves, 1);
    expect(fake.games.single.cover, isNull);
    expect(find.text('Added DEMO. Cover download failed.'), findsOneWidget);
    await _drainToast(tester);
  });

  testWidgets('Add without VNDB opens step 2 with a placeholder cover', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.byKey(const Key('add-game-manual')));
    await tester.pumpAndSettle();
    expect(find.text('Details'), findsOneWidget);
    expect(find.byKey(const Key('add-game-description')), findsOneWidget);
    expect(find.text('New game'), findsOneWidget);
    expect(find.byIcon(Icons.image_not_supported_outlined), findsOneWidget);
    expect(find.widgetWithText(BrandGlassButton, 'Back'), findsOneWidget);
    expect(find.widgetWithText(BrandGlassButton, 'Cancel'), findsOneWidget);
  });

  testWidgets('the dialog is 960 by 720 at 1400 by 980', (tester) async {
    await _pump(tester, surface: const Size(1400, 980));
    expect(
      tester.getSize(find.byKey(const Key('add-game-frame'))),
      const Size(960, 720),
    );
  });

  testWidgets('nothing overflows in the dialog at 1000 by 640', (tester) async {
    final (_, http, _) = await _pump(
      tester,
      surface: const Size(1000, 640),
      rows: [
        _row('v900017', 'DEMO', imageUrl: null, tags: ['Romance']),
      ],
    );
    expect(tester.takeException(), isNull);
    await _search(tester, 'DEMO', http);
    expect(tester.takeException(), isNull);
    await tester.tap(_resultRow('DEMO'));
    await tester.pumpAndSettle();
    await _next(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the manual path requires a title', (tester) async {
    final (fake, _, _) = await _pump(
      tester,
      rows: [_row('v900017', 'DEMO', imageUrl: null)],
    );
    await tester.tap(find.byKey(const Key('add-game-manual')));
    await tester.pumpAndSettle();
    expect(find.text('Details'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('add-game-title')), '');
    await tester.tap(find.byKey(const Key('add-game-add')));
    await tester.pumpAndSettle();
    expect(find.text('Title is required'), findsOneWidget);
    expect(fake.saves, 0);
    await tester.enterText(find.byKey(const Key('add-game-title')), 'My Game');
    await tester.enterText(
      find.byKey(const Key('add-game-exe')),
      '/games/mine/run.exe',
    );
    await tester.tap(find.byKey(const Key('add-game-add')));
    await tester.pumpAndSettle();
    expect(fake.saves, 1);
    expect(fake.games.single.title, 'My Game');
    expect(fake.games.single.vndbId, isNull);
    expect(find.text('Added My Game'), findsOneWidget);
    await _drainToast(tester);
  });

  testWidgets('a network error shows Retry', (tester) async {
    final (_, http, _) = await _pump(
      tester,
      rows: [_row('v900017', 'DEMO', imageUrl: null)],
    );
    http.failSearch = true;
    await _search(tester, 'DEMO 2', http);
    expect(find.byKey(const Key('add-game-retry')), findsOneWidget);
    http.failSearch = false;
    await tester.tap(find.byKey(const Key('add-game-retry')));
    await tester.pumpAndSettle();
    expect(find.text('DEMO'), findsWidgets);
  });

  testWidgets('no results shows the empty text', (tester) async {
    final (_, http, _) = await _pump(tester, rows: []);
    await _search(tester, 'zzz-no-such-game', http);
    expect(find.text('No matches on VNDB'), findsOneWidget);
  });

  testWidgets('the search field has focus in the match step', (tester) async {
    await _pump(tester, rows: [_row('v900017', 'DEMO', imageUrl: null)]);
    bool searchFocused() => tester
        .widget<EditableText>(
          find.descendant(
            of: find.byKey(const Key('add-game-search')),
            matching: find.byType(EditableText),
          ),
        )
        .focusNode
        .hasFocus;
    expect(searchFocused(), isTrue);
  });

  testWidgets(
    'manual setup boxes are 40 px and the placeholder cover is 220 by 293',
    (tester) async {
      await _pump(tester);
      await tester.tap(find.byKey(const Key('add-game-manual')));
      await tester.pumpAndSettle();
      Finder boxOf(String key) => find.descendant(
        of: find.byKey(Key(key)),
        matching: find.byType(InputDecorator),
      );
      Finder borderOf(String key) => find.descendant(
        of: find.byKey(Key(key)),
        matching: find.byType(SettingsTextBox),
      );
      for (final key in ['add-game-title', 'add-game-exe']) {
        expect(tester.getSize(boxOf(key)).height, closeTo(40, 1), reason: key);
        expect(
          tester.getSize(borderOf(key)).height,
          closeTo(40, 1),
          reason: '$key border',
        );
      }
      final exe = tester.getCenter(borderOf('add-game-exe')).dy;
      final choose = tester
          .getCenter(find.byKey(const Key('add-game-exe-choose')))
          .dy;
      expect((exe - choose).abs(), lessThanOrEqualTo(1));
      final placeholder = find.ancestor(
        of: find.byIcon(Icons.image_not_supported_outlined),
        matching: find.byType(Container),
      );
      expect(tester.getSize(placeholder.first), const Size(220, 293));
      expect(find.text('New game'), findsOneWidget);
    },
  );

  testWidgets('add text is centred in each box, unfocused and focused', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.byKey(const Key('add-game-manual')));
    await tester.pumpAndSettle();
    for (final key in ['add-game-title', 'add-game-exe']) {
      final box = find.descendant(
        of: find.byKey(Key(key)),
        matching: find.byType(SettingsTextBox),
      );
      final editable = find.descendant(
        of: find.byKey(Key(key)),
        matching: find.byType(EditableText),
      );
      expect(
        tester.getCenter(editable).dy,
        closeTo(tester.getCenter(box).dy + 4, 2),
        reason: '$key unfocused',
      );
      await tester.tap(editable);
      await tester.pump();
      expect(
        tester.getCenter(editable).dy,
        closeTo(tester.getCenter(box).dy + 4, 2),
        reason: '$key focused',
      );
      await tester.enterText(find.byKey(Key(key)), 'typed value');
      await tester.pump();
      expect(
        tester.getCenter(editable).dy,
        closeTo(tester.getCenter(box).dy + 4, 2),
        reason: '$key typing',
      );
    }
  });

  testWidgets('a tag typed but not confirmed is saved with the game', (
    tester,
  ) async {
    final (fake, _, _) = await _pump(tester);
    await tester.tap(find.byKey(const Key('add-game-manual')));
    await tester.pumpAndSettle();
    await _fillManual(tester);
    await tester.tap(find.byKey(const Key('add-game-tag-add')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('add-game-tag-input')),
      'Mystery',
    );
    await tester.tap(find.byKey(const Key('add-game-add')));
    await _waitForSave(tester, fake);
    expect(fake.games.single.tags, ['Mystery']);
    await _drainToast(tester);
  });

  testWidgets('commas split typed tags and duplicates are skipped', (
    tester,
  ) async {
    final (fake, _, _) = await _pump(tester);
    await tester.tap(find.byKey(const Key('add-game-manual')));
    await tester.pumpAndSettle();
    await _fillManual(tester);
    await tester.tap(find.byKey(const Key('add-game-tag-add')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('add-game-tag-input')),
      'Alpha, beta, ALPHA, , gamma',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.byType(TagChip), findsNWidgets(3));
    await tester.tap(find.byKey(const Key('add-game-add')));
    await _waitForSave(tester, fake);
    expect(fake.games.single.tags, ['Alpha', 'beta', 'gamma']);
    await _drainToast(tester);
  });

  testWidgets('close is ignored while saving and the game is still added', (
    tester,
  ) async {
    final (fake, _, _) = await _pump(tester);
    fake.saveGate = Completer<void>();
    await tester.tap(find.byKey(const Key('add-game-manual')));
    await tester.pumpAndSettle();
    await _fillManual(tester);
    await tester.tap(find.byKey(const Key('add-game-add')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('add-game-close')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Details'), findsOneWidget);
    fake.saveGate!.complete();
    await _waitForSave(tester, fake);
    expect(fake.games.single.title, 'Manual game');
    await _drainToast(tester);
  });

  testWidgets('the start step shows the drop zone and two cards', (
    tester,
  ) async {
    await _pump(tester, openMatch: false);
    expect(find.text('Drop a game folder or file here'), findsOneWidget);
    expect(find.text('Choose folder…'), findsOneWidget);
    expect(find.text('Choose game file…'), findsOneWidget);
    expect(find.text('Steam games'), findsOneWidget);
    expect(find.text('Installed on this computer'), findsOneWidget);
    expect(find.text('Import folder'), findsOneWidget);
  });

  testWidgets('Choose game file matches the file folder with that file', (
    tester,
  ) async {
    await _pump(
      tester,
      openMatch: false,
      rows: [_row('v900017', 'DEMO', imageUrl: null)],
    );
    await _chooseFolder(tester, key: 'add-game-choose-file');
    expect(find.text('Match on VNDB'), findsOneWidget);
    expect(find.text('DEMO.exe'), findsWidgets);
    final search = tester.widget<TextField>(
      find.byKey(const Key('add-game-search')),
    );
    expect(search.controller!.text, 'DEMO');
  });

  testWidgets('the Steam card opens the installed Steam games', (tester) async {
    await _pump(tester, openMatch: false, steamGames: (_) async => []);
    await tester.tap(find.byKey(const Key('add-game-steam')));
    for (
      var i = 0;
      i < 100 && find.text('No Steam games to add.').evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(find.text('Select Steam games'), findsOneWidget);
    expect(find.text('No Steam games to add.'), findsOneWidget);
  });

  testWidgets('the Import card opens the import dialog', (tester) async {
    await _pump(tester, openMatch: false);
    await tester.tap(find.byKey(const Key('add-game-import')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('import-close')), findsOneWidget);
  });

  testWidgets('Find on VNDB from Steam setup returns to setup with the pick', (
    tester,
  ) async {
    // A game folder inside a Steam library is detected as a Steam game, so
    // its setup step carries the Steam App ID field.
    final steamTemp = Directory.systemTemp.createTempSync(
      'tsumige_add_steam_test_',
    );
    addTearDown(() => steamTemp.deleteSync(recursive: true));
    final gameDir =
        Directory(p.join(steamTemp.path, 'steamapps', 'common', 'DEMO'))
          ..createSync(recursive: true);
    File(
      p.join(steamTemp.path, 'steamapps', 'appmanifest_480.acf'),
    ).writeAsStringSync(
      '"AppState"\n{\n"appid"\t\t"480"\n"name"\t\t"DEMO"\n'
      '"installdir"\t\t"DEMO"\n}\n',
    );
    await _pump(
      tester,
      openMatch: false,
      rows: [_row('v900017', 'DEMO', imageUrl: null)],
      pickFolder: (_) => gameDir.path,
    );
    await _chooseFolder(tester);
    await _next(tester);
    // Detection reads the Steam manifest from real files, so poll with
    // real time the way the import tests settle their disk scan.
    for (
      var i = 0;
      i < 100 && find.text('Steam App ID').evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(find.text('Details'), findsOneWidget);
    expect(find.text('Steam App ID'), findsOneWidget);
    expect(
      tester
          .widget<SettingsTextBox>(
            find.byKey(const Key('add-game-steam-app-id')),
          )
          .controller!
          .text,
      '480',
    );
    await tester.tap(find.byKey(const Key('add-game-find-vndb')));
    await tester.pumpAndSettle();
    expect(find.text('Match on VNDB'), findsOneWidget);
    await tester.tap(_resultRow('DEMO'));
    await tester.pumpAndSettle();
    await _next(tester);
    for (
      var i = 0;
      i < 100 && find.text('Match on VNDB').evaluate().isNotEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(find.text('Details'), findsOneWidget);
    expect(find.text('Steam App ID'), findsOneWidget);
    expect(find.text('DEMO'), findsWidgets);
  });

  testWidgets('a folder match is the best match and is selected', (
    tester,
  ) async {
    await _pump(tester, rows: [_row('v900017', 'DEMO', imageUrl: null)]);
    expect(find.text('Best match'), findsOneWidget);
    await _next(tester);
    expect(find.text('Details'), findsOneWidget);
    expect(find.text('DEMO'), findsWidgets);
  });

  testWidgets('no best match and Next is disabled when nothing matches', (
    tester,
  ) async {
    await _pump(
      tester,
      rows: [_row('v1', 'Completely Different Title', imageUrl: null)],
    );
    expect(find.text('Best match'), findsNothing);
    final next = tester.widget<BrandButton>(
      find.byKey(const Key('add-game-next')),
    );
    expect(next.onPressed, isNull);
  });

  testWidgets('a selected result shows its detail panel', (tester) async {
    await _pump(tester, rows: [_row('v900017', 'DEMO', imageUrl: null)]);
    expect(find.text('Selected'), findsOneWidget);
    expect(find.text('Sample Studio'), findsWidgets);
  });

  testWidgets('picking a library exe through a symlink blocks Add', (
    tester,
  ) async {
    final temp = Directory.systemTemp.createTempSync('tsumige_add_dup_test_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final real = Directory(p.join(temp.path, 'real'))..createSync();
    final alphaExe = p.join(real.path, 'Alpha.exe');
    File(alphaExe).writeAsBytesSync([0, 1, 2]);
    Link(p.join(temp.path, 'link')).createSync(real.path);
    final (fake, _, _) = await _pump(
      tester,
      games: [
        core.Game(
          id: 'a',
          title: 'Alpha',
          launch: core.LaunchOverrides(executable: alphaExe),
        ),
      ],
    );
    await tester.tap(find.byKey(const Key('add-game-manual')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('add-game-title')),
      'Alpha copy',
    );
    await tester.enterText(
      find.byKey(const Key('add-game-exe')),
      p.join(temp.path, 'link', 'Alpha.exe'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Already in library as Alpha.'), findsOneWidget);
    final add = tester.widget<BrandButton>(
      find.byKey(const Key('add-game-add')),
    );
    expect(add.onPressed, isNull);
    expect(fake.saves, 0);
  });

  testWidgets('a dropped folder on the start step opens the match step',
      (tester) async {
    await _pump(tester, openMatch: false);
    _dropOn(tester, [DropItemDirectory(_tempFolder(), const [])]);
    await _untilShown(tester, 'Match on VNDB');
    expect(find.text('Match on VNDB'), findsOneWidget);
  });

  testWidgets('dropped several folders open the import dialog',
      (tester) async {
    await _pump(tester, openMatch: false);
    _dropOn(tester, [
      DropItemDirectory(_tempFolder(), const []),
      DropItemDirectory(_tempFolder(), const []),
    ]);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('import-close')), findsOneWidget);
  });

  testWidgets('a drop on the library opens the match step for that folder',
      (tester) async {
    await _pump(tester, openMatch: false);
    await tester.tap(find.byKey(const Key('add-game-close')));
    await tester.pumpAndSettle();
    final context = tester.element(find.text('open'));
    unawaited(dropOntoLibrary(context, [_tempFolder()]));
    await _untilShown(tester, 'Match on VNDB');
    expect(find.text('Match on VNDB'), findsOneWidget);
    expect(find.text('DEMO.exe'), findsWidgets);
  });

  testWidgets('a dropped folder of several games opens the import dialog',
      (tester) async {
    await _pump(tester, openMatch: false);
    final root = _multiGameFolder();
    _dropOn(tester, [DropItemDirectory(root, const [])]);
    await _untilShown(tester, 'Alpha');
    expect(find.byKey(const Key('import-close')), findsOneWidget);
    expect(find.text('Alpha'), findsWidgets);
    expect(find.text('Beta'), findsWidgets);
  });

  testWidgets('a failing folder dialog shows a toast instead of nothing', (
    tester,
  ) async {
    await _pump(
      tester,
      openMatch: false,
      pickError: PlatformException(code: 'picker'),
    );
    await tester.tap(find.byKey(const Key('add-game-choose-folder')));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't open the file dialog."), findsOneWidget);
    expect(find.text('Match on VNDB'), findsNothing);
    await _drainToast(tester);
  });

  testWidgets('Choose folder with several games opens the import dialog',
      (tester) async {
    final root = _multiGameFolder();
    await _pump(tester, openMatch: false, pickFolder: (_) => root);
    await tester.tap(find.byKey(const Key('add-game-choose-folder')));
    await _untilShown(tester, 'Alpha');
    expect(find.byKey(const Key('import-close')), findsOneWidget);
    expect(find.text('Alpha'), findsWidgets);
    expect(find.text('Beta'), findsWidgets);
  });
}

/// A throwaway folder holding two game folders, deleted with the test run.
String _multiGameFolder() {
  final root = Directory.systemTemp.createTempSync('tsumige_multi_test_');
  addTearDown(() => root.deleteSync(recursive: true));
  for (final name in ['Alpha', 'Beta']) {
    final game = Directory(p.join(root.path, name))..createSync();
    File(p.join(game.path, '$name.exe')).writeAsBytesSync([0, 1, 2]);
  }
  return root.path;
}

/// A throwaway folder holding DEMO.exe, deleted with the test directory.
String _tempFolder() {
  final folder = Directory.systemTemp.createTempSync('tsumige_drop_test_');
  File(p.join(folder.path, 'DEMO.exe')).writeAsBytesSync([0, 1, 2]);
  return folder.path;
}

void _dropOn(WidgetTester tester, List<DropItem> items) {
  final target = tester.widget<DropTarget>(find.byType(DropTarget).first);
  target.onDragDone!(DropDoneDetails(
    files: items,
    localPosition: Offset.zero,
    globalPosition: Offset.zero,
  ));
}

Future<void> _untilShown(WidgetTester tester, String text) async {
  for (var i = 0; i < 100 && find.text(text).evaluate().isEmpty; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Future<void> _fillManual(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('add-game-title')),
    'Manual game',
  );
  await tester.enterText(
    find.byKey(const Key('add-game-exe')),
    '/games/manual/run.exe',
  );
  await tester.pump();
}
