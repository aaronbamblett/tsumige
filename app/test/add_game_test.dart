// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vnl/src/core/covers.dart' as core;
import 'package:vnl/src/core/model.dart' as core;
import 'package:vnl/src/core/paths.dart' as core;
import 'package:vnl/src/core/vndb.dart' as core;
import 'package:vnl/src/features/library/data/library_repository.dart';
import 'package:vnl/src/features/library/domain/add_game.dart';
import 'package:vnl/src/features/library/domain/selection.dart';
import 'package:vnl/src/features/library/presentation/add_game/add_game_dialog.dart';
import 'package:vnl/src/utils/prefs/prefs_mixin.dart';
import 'package:vnl/src/utils/theme/brand.dart';

class _FakeRepository implements LibraryRepository {
  _FakeRepository(this.games);

  final List<core.Game> games;
  int saves = 0;

  @override
  Future<core.LoadedLibrary> load() async =>
      core.LoadedLibrary(library: core.Library(games: games));

  @override
  Future<void> save(core.LoadedLibrary loaded) async {
    saves++;
  }

  @override
  Future<core.VndbRefreshReport> refreshVndbData(core.LoadedLibrary loaded) async =>
      const core.VndbRefreshReport();

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
                jsonEncode({'results': releaseRows, 'more': false}), 200);
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
          return http.Response(
              jsonEncode({'results': rows, 'more': false}), 200);
        }
        gets++;
        final bytes = coverBytes;
        if (bytes == null) return http.Response('missing', 404);
        return http.Response.bytes(bytes, 200);
      });
}

Map<String, Object?> _row(String id, String title,
    {String? alttitle,
    String released = '2020-06-19',
    double? rating = 85.0,
    int votecount = 42,
    String? imageUrl,
    String description = 'A story.',
    List<String> developers = const ['Sample Studio'],
    List<String> tags = const ['Romance', 'Drama']}) {
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
    'developers': [for (final d in developers) {'name': d}],
    'tags': [
      for (final t in tags) {'name': t, 'rating': 80.0, 'spoiler': 0}
    ],
  };
}

Uint8List _png() => img.encodePng(img.Image(width: 8, height: 8));

Future<(_FakeRepository, _Http, ProviderContainer)> _pump(
    WidgetTester tester,
    {List<core.Game> games = const [],
    List<Map<String, Object?>> rows = const []}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final temp = Directory.systemTemp.createTempSync('vnl_add_game_test_');
  addTearDown(() => temp.deleteSync(recursive: true));
  SharedPreferences.setMockInitialValues({});
  final fake = _FakeRepository([...games]);
  final http = _Http(rows: rows);
  late ProviderContainer container;
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider
          .overrideWithValue(await SharedPreferences.getInstance()),
      dataDirProvider.overrideWithValue(core.DataDir(temp.path)),
      libraryRepositoryProvider.overrideWithValue(fake),
      addGameHttpClientProvider.overrideWithValue(http.client),
    ],
    child: MaterialApp(
      builder: FToastBuilder(),
      home: Builder(builder: (context) {
        container = ProviderScope.containerOf(context);
        return Scaffold(
          body: TextButton(
            onPressed: () => showAddGameDialog(context),
            child: const Text('open'),
          ),
        );
      }),
    ),
  ));
  await tester.pump();
  await tester.pump();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  expect(find.text('Find on VNDB'), findsOneWidget);
  return (fake, http, container);
}

Future<void> _search(
    WidgetTester tester, String query, _Http http) async {
  await tester.enterText(find.byKey(const Key('add-game-search')), query);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
  await tester.pump();
}

// find.text also matches the search field's editable text, so row taps must
// be scoped to the result list.
Finder _resultRow(String title) => find.descendant(
      of: find.byType(ListTile),
      matching: find.text(title),
    );

// The cover pipeline runs on isolates, which pumpAndSettle does not wait for.
// Poll in real time until the save lands, then settle and drain toast timers.
Future<void> _waitForSave(WidgetTester tester, _FakeRepository fake) async {
  for (var i = 0; i < 200 && fake.saves == 0; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

// FToast dismisses on a 3-second timer that outlives pumpAndSettle, so drain
// it after the toast assertions or teardown fails on a pending timer.
Future<void> _drainToast(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 6));

void main() {
  testWidgets('typing searches once after the debounce', (tester) async {
    final (_, http, _) = await _pump(tester,
        rows: [_row('v900017', 'DEMO', imageUrl: null)]);
    await tester.enterText(
        find.byKey(const Key('add-game-search')), 'DEMO');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 399));
    expect(http.posts, 0);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    await tester.pump();
    expect(http.posts, 1);
    expect(find.text('DEMO'), findsWidgets);
  });

  testWidgets('results render with metadata', (tester) async {
    final (_, http, _) = await _pump(tester, rows: [
      _row('v900017', 'DEMO', alttitle: 'Demo', imageUrl: null),
      _row('v1', 'Unrated Game',
          imageUrl: null,
          rating: null,
          released: '2019-03-01',
          developers: ['Other Dev']),
    ]);
    await _search(tester, 'DEMO', http);
    expect(find.text('DEMO'), findsWidgets);
    expect(find.text('Unrated Game'), findsOneWidget);
    expect(find.text('Demo'), findsOneWidget);
    expect(find.textContaining('2020'), findsOneWidget);
    expect(find.textContaining('Sample Studio'), findsOneWidget);
    expect(find.text('VNDB Rating 8.5'), findsOneWidget);
  });

  testWidgets('an In library result cannot be picked', (tester) async {
    final (_, http, _) = await _pump(tester,
        games: [core.Game(id: 'g1', title: 'Owned', vndbId: 'v900017')],
        rows: [
          _row('v900017', 'DEMO', imageUrl: null),
          _row('v1', 'Other Game', imageUrl: null),
        ]);
    await _search(tester, 'DEMO', http);
    expect(find.text('In library'), findsOneWidget);
    await tester.tap(_resultRow('DEMO'));
    await tester.pumpAndSettle();
    expect(find.text('Set it up'), findsNothing);
    await tester.tap(_resultRow('Other Game'));
    await tester.pumpAndSettle();
    expect(find.text('Set it up'), findsOneWidget);
  });

  testWidgets('picking moves to step 2 with the fields filled',
      (tester) async {
    final (_, http, _) = await _pump(tester, rows: [
      _row('v900017', 'DEMO',
          imageUrl: null, description: 'A story.', tags: ['Romance'])
    ]);
    await _search(tester, 'DEMO', http);
    await tester.tap(_resultRow('DEMO'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('add-game-title')))
            .controller!
            .text,
        'DEMO');
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('add-game-description')))
            .controller!
            .text,
        'A story.');
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('add-game-tags')))
            .controller!
            .text,
        'Romance');
    expect(find.widgetWithText(BrandButton, 'Add'), findsOneWidget);
    expect(find.widgetWithText(BrandGlassButton, 'Back'), findsOneWidget);
  });

  testWidgets('Add with no exe and a non-Steam mode needs an executable',
      (tester) async {
    final (_, http, _) = await _pump(tester,
        rows: [_row('v900017', 'DEMO', imageUrl: null)]);
    await _search(tester, 'DEMO', http);
    await tester.tap(_resultRow('DEMO'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-game-add')));
    await tester.pumpAndSettle();
    expect(find.text('Executable is required'), findsOneWidget);
  });

  testWidgets('Add saves through the repository and selects the game',
      (tester) async {
    final (fake, http, container) = await _pump(tester, rows: [
      _row('v900017', 'DEMO',
          imageUrl: 'http://127.0.0.1:9/cover.jpg', tags: ['Romance'])
    ]);
    http.coverBytes = _png();
    await _search(tester, 'DEMO', http);
    await tester.tap(_resultRow('DEMO'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('add-game-exe')), '/games/demo/run.exe');
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
    final (fake, http, _) = await _pump(tester, rows: [
      _row('v900017', 'DEMO', imageUrl: null)
    ]);
    http.metadataRows = [
      {
        'id': 'v900017',
        'alttitle': 'デモ',
        'length_minutes': 1200,
        'length_votes': 88,
        'olang': 'ja',
        'developers': [
          {'id': 'p1', 'name': 'Sample Studio'}
        ],
        'tags': [
          {'name': 'Romance', 'rating': 2.5, 'spoiler': 0, 'category': 'cont'}
        ],
        'relations': [],
      }
    ];
    http.releaseRows = [
      {
        'vns': [
          {'id': 'v900017'}
        ]
      }
    ];
    await _search(tester, 'DEMO', http);
    await tester.tap(_resultRow('DEMO'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('add-game-exe')), '/games/demo/run.exe');
    await tester.tap(find.byKey(const Key('add-game-add')));
    await _waitForSave(tester, fake);
    expect(fake.saves, 1);
    final game = fake.games.single;
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
    final (fake, http, _) = await _pump(tester, rows: [
      _row('v900017', 'DEMO', imageUrl: null)
    ]);
    http.failMetadata = true;
    await _search(tester, 'DEMO', http);
    await tester.tap(_resultRow('DEMO'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('add-game-exe')), '/games/demo/run.exe');
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

  testWidgets('a cover download failure still adds the game',
      (tester) async {
    final (fake, http, _) = await _pump(tester, rows: [
      _row('v900017', 'DEMO', imageUrl: 'http://127.0.0.1:9/cover.jpg')
    ]);
    await _search(tester, 'DEMO', http);
    await tester.tap(_resultRow('DEMO'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('add-game-exe')), '/games/demo/run.exe');
    await tester.tap(find.byKey(const Key('add-game-add')));
    await tester.pumpAndSettle();
    expect(fake.saves, 1);
    expect(fake.games.single.cover, isNull);
    expect(find.text('Added DEMO (cover download failed)'), findsOneWidget);
    await _drainToast(tester);
  });

  testWidgets('the manual path requires a title', (tester) async {
    final (fake, _, _) =
        await _pump(tester, rows: [_row('v900017', 'DEMO', imageUrl: null)]);
    await tester.tap(find.byKey(const Key('add-game-manual')));
    await tester.pumpAndSettle();
    expect(find.text('Set it up'), findsOneWidget);
    await tester.tap(find.byKey(const Key('add-game-add')));
    await tester.pumpAndSettle();
    expect(find.text('Title is required'), findsOneWidget);
    expect(fake.saves, 0);
    await tester.enterText(
        find.byKey(const Key('add-game-title')), 'My Game');
    await tester.enterText(
        find.byKey(const Key('add-game-exe')), '/games/mine/run.exe');
    await tester.tap(find.byKey(const Key('add-game-add')));
    await tester.pumpAndSettle();
    expect(fake.saves, 1);
    expect(fake.games.single.title, 'My Game');
    expect(fake.games.single.vndbId, isNull);
    expect(find.text('Added My Game'), findsOneWidget);
    await _drainToast(tester);
  });

  testWidgets('a network error shows Retry', (tester) async {
    final (_, http, _) = await _pump(tester,
        rows: [_row('v900017', 'DEMO', imageUrl: null)]);
    http.failSearch = true;
    await _search(tester, 'DEMO', http);
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
}
