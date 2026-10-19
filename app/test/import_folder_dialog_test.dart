// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
import 'package:tsumige/src/core/host_platform.dart';
import 'package:tsumige/src/core/vndb.dart' as core;
import 'package:tsumige/src/features/library/data/library_repository.dart';
import 'package:tsumige/src/features/library/presentation/widgets/dialog_shell.dart';
import 'package:tsumige/src/features/library/domain/add_game.dart';
import 'package:tsumige/src/features/library/domain/game_editor.dart';
import 'package:tsumige/src/features/library/presentation/add_game/add_game_dialog.dart';
import 'package:tsumige/src/features/library/presentation/add_game/import_folder_dialog.dart';
import 'package:tsumige/src/utils/platform/platform_runtime.dart';
import 'package:tsumige/src/features/settings/presentation/sections/settings_widgets.dart';
import 'package:tsumige/src/utils/theme/brand.dart';
import 'package:tsumige/src/utils/prefs/prefs_mixin.dart';

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

/// Fake VNDB keyed by search query. Cover URLs containing "fail" return 404.
class _Vndb {
  _Vndb(this.byQuery, {this.gateQuery, this.gate});

  final Map<String, List<Map<String, Object?>>> byQuery;
  final String? gateQuery;
  final Completer<void>? gate;

  MockClient get client => MockClient((request) async {
    if (request.method == 'POST') {
      final body = jsonDecode(request.body) as Map;
      final filters = body['filters'] as List;
      if (filters.first == 'search') {
        final query = filters[2] as String;
        if (query == gateQuery) await gate!.future;
        return http.Response(
          jsonEncode({'results': byQuery[query] ?? [], 'more': false}),
          200,
        );
      }
      return http.Response(jsonEncode({'results': [], 'more': false}), 200);
    }
    if (request.url.toString().contains('fail')) {
      return http.Response('missing', 404);
    }
    return http.Response.bytes(
      img.encodePng(img.Image(width: 8, height: 8)),
      200,
    );
  });
}

Map<String, Object?> _vnRow(
  String id,
  String title, {
  String imageUrl = 'http://127.0.0.1:9/cover.jpg',
}) {
  return {
    'id': id,
    'title': title,
    'titles': [],
    'released': '2020-06-19',
    'rating': 85.0,
    'votecount': 42,
    'image': {'url': imageUrl, 'sexual': 0},
    'description': 'A story.',
    'developers': [
      {'name': 'Sample Studio'},
    ],
    'tags': [
      {'name': 'Romance', 'rating': 80.0, 'spoiler': 0},
    ],
  };
}

Map<String, List<Map<String, Object?>>> _defaultResults() => {
  'DEMO': [_vnRow('v900017', 'DEMO')],
  'Owned Game': [_vnRow('v99', 'Owned Game')],
  'Rena sensei': [
    _vnRow(
      'v5',
      'Rena-sensei to Pool Ryokou',
      imageUrl: 'http://127.0.0.1:9/rena.jpg',
    ),
  ],
  'Solo Quest': [
    _vnRow('v7', 'Solo Quest Remake'),
    _vnRow('v8', 'Solo Quest Remaster'),
  ],
  'DEMO Copy': [_vnRow('v900017', 'DEMO')],
};

void _exe(String root, String relative) {
  final file = File(p.join(root, relative));
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync([0, 1, 2]);
}

/// Root "Visual novels" with five subfolders:
///  DEMO          exact match, pre-ticked
///  Nothing Here  an exe, no match
///  Owned Game    matches a library game, disabled
///  Rena sensei   close match, pre-ticked
///  Solo Quest    two results (check match), two exes
String _fixture(Directory temp, {bool duplicate = false, bool macos = false}) {
  final root = p.join(temp.path, 'Visual novels');
  void launch(String relative) {
    if (!macos) {
      _exe(root, relative);
      return;
    }
    final bundle = p.join(root, '${p.withoutExtension(relative)}.app');
    Directory(bundle).createSync(recursive: true);
  }

  launch('DEMO/DEMO.exe');
  _exe(root, 'DEMO/unins000.exe');
  launch('Nothing Here/Nothing.exe');
  launch('Owned Game/Owned.exe');
  launch('Rena sensei/RenaPool.exe');
  launch('Solo Quest/Solo.exe');
  launch('Solo Quest/bin/Extra.exe');
  if (duplicate) launch('DEMO Copy/demo copy.exe');
  return root;
}

class _Harness {
  _Harness(this.repo, this.root);

  final _FakeRepository repo;
  final String root;
  ImportFolderResult? result;
}

/// Opens the import dialog directly over a fixture folder.
core.Game _ownedGame() => core.Game(id: 'g1', title: 'Owned', vndbId: 'v99');

Future<_Harness> _open(
  WidgetTester tester, {
  List<core.Game>? games,
  Map<String, List<Map<String, Object?>>>? results,
  Size surface = const Size(1400, 980),
  bool duplicate = false,
  Completer<void>? gate,
  String? gateQuery,
  Completer<String?>? picker,
  HostPlatform? platform,
}) async {
  tester.view.physicalSize = surface;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final temp = Directory.systemTemp.createTempSync(
    'tsumige_import_dialog_test_',
  );
  addTearDown(() => temp.deleteSync(recursive: true));
  final root = _fixture(
    temp,
    duplicate: duplicate,
    macos: platform?.isMacOS ?? false,
  );
  SharedPreferences.setMockInitialValues({});
  final repo = _FakeRepository([
    ...(games ?? [_ownedGame()]),
  ]);
  final vndb = _Vndb(
    results ?? _defaultResults(),
    gate: gate,
    gateQuery: gateQuery,
  );
  final harness = _Harness(repo, root);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
        dataDirProvider.overrideWithValue(core.DataDir(temp.path)),
        libraryRepositoryProvider.overrideWithValue(repo),
        addGameHttpClientProvider.overrideWithValue(vndb.client),
        pathPickerProvider.overrideWithValue(
          ({String? initialDirectory, PathPickMode? mode}) async =>
              picker != null ? picker.future : root,
        ),
        if (platform != null) hostPlatformProvider.overrideWithValue(platform),
      ],
      child: MaterialApp(
        builder: FToastBuilder(),
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () async {
                  harness.result = await showImportFolderDialog(context);
                },
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
  await tester.pump();
  return harness;
}

/// Opens the dialog and waits for the disk scan and the VNDB matching. The
/// scan reads real files, so poll with real time; each VNDB query waits a
/// second of fake time.
Future<_Harness> _openAndMatch(
  WidgetTester tester, {
  List<core.Game>? games,
  Map<String, List<Map<String, Object?>>>? results,
  Size surface = const Size(1400, 980),
  bool duplicate = false,
  int folders = 5,
  HostPlatform? platform,
}) async {
  final harness = await _open(
    tester,
    games: games,
    results: results,
    surface: surface,
    duplicate: duplicate,
    platform: platform,
  );
  for (var i = 0; i < 200; i++) {
    if (find.byKey(const Key('import-check-0')).evaluate().isNotEmpty) break;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  for (var i = 0; i <= folders; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
  await tester.pump();
  return harness;
}

List<core.Game> _added(_Harness h) => h.repo.games.skip(1).toList();

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _waitForSave(WidgetTester tester, _FakeRepository fake) async {
  for (var i = 0; i < 200 && fake.saves == 0; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  await tester.pump();
}

// FToast dismisses on a 3-second timer that outlives the test body.
Future<void> _drainToast(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 6));

bool _checked(WidgetTester tester, int index) =>
    tester.widget<Checkbox>(find.byKey(Key('import-check-$index'))).value!;

void main() {
  testWidgets(
    'rows show confident matches with their VNDB title and the rest with the folder name',
    (tester) async {
      final h = await _openAndMatch(tester);
      expect(find.text('Select games to import'), findsOneWidget);
      expect(find.text('Add games'), findsOneWidget);
      expect(find.text('DEMO'), findsOneWidget);
      expect(find.text('Rena-sensei to Pool Ryokou'), findsOneWidget);
      expect(find.text('Solo Quest'), findsNothing);
      expect(find.text('Solo Quest Remake'), findsOneWidget);
      expect(find.text('Best match'), findsOneWidget);
      expect(find.text('Nothing Here'), findsOneWidget);
      expect(find.text('Owned Game'), findsNothing);
      expect(find.text('Matched'), findsNothing);
      expect(find.text('Check match'), findsNothing);
      expect(find.text('Pick the game file'), findsNothing);
      expect(
        tester
            .widget<MiddleEllipsisText>(find.byType(MiddleEllipsisText).first)
            .text,
        p.join(h.root, 'DEMO', 'DEMO.exe'),
      );
      expect(_checked(tester, 0), isTrue);
      expect(_checked(tester, 1), isFalse);
      expect(_checked(tester, 3), isTrue);
      expect(_checked(tester, 4), isFalse);
    },
  );

  testWidgets('the hide imported checkbox shows library rows disabled', (
    tester,
  ) async {
    await _openAndMatch(
      tester,
      games: [core.Game(id: 'g1', title: 'Owned', vndbId: 'v99')],
    );
    expect(find.byKey(const Key('import-check-2')), findsNothing);
    await tester.tap(find.byKey(const Key('import-hide-imported')));
    await tester.pump();
    expect(find.text('Owned Game'), findsOneWidget);
    expect(
      tester
          .widget<Checkbox>(find.byKey(const Key('import-check-2')))
          .onChanged,
      isNull,
    );
    await tester.tap(find.byKey(const Key('import-check-2')));
    await tester.pump();
    expect(find.text('Add Games'), findsOneWidget);
  });

  testWidgets('Scan Folder does not list a folder twice', (tester) async {
    await _openAndMatch(tester);
    await tester.tap(find.byKey(const Key('import-scan')));
    await _settle(tester);
    expect(find.byKey(const Key('import-check-4')), findsOneWidget);
    expect(find.byKey(const Key('import-check-5')), findsNothing);
    expect(find.text('Rena-sensei to Pool Ryokou'), findsOneWidget);
  });

  testWidgets('the header checkbox ticks every eligible row', (tester) async {
    final h = await _openAndMatch(tester);
    await tester.tap(find.byKey(const Key('import-check-all')));
    await tester.pump();
    expect(_checked(tester, 0), isTrue);
    expect(_checked(tester, 1), isTrue);
    expect(_checked(tester, 3), isTrue);
    expect(_checked(tester, 4), isTrue);
    await tester.tap(find.byKey(const Key('import-check-all')));
    await tester.pump();
    expect(_checked(tester, 0), isFalse);
    expect(h.repo.saves, 0);
  });

  testWidgets('clicking a name opens the picker with the cleaned name', (
    tester,
  ) async {
    await _openAndMatch(tester);
    await tester.tap(find.byKey(const Key('import-name-4')));
    await tester.pump();
    expect(find.text('Select item'), findsOneWidget);
    expect(find.text('Solo Quest'), findsWidgets);
    expect(
      find.text('Search by title, or paste a VNDB link or ID (v12345).'),
      findsOneWidget,
    );
    expect(find.text('Selected'), findsOneWidget);
    expect(
      tester
          .widget<BrandButton>(find.byKey(const Key('import-pick-select')))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.text('Solo Quest Remaster'));
    await _settle(tester);
    expect(find.text('Selected'), findsOneWidget);
    await tester.tap(find.byKey(const Key('import-pick-select')));
    await _settle(tester);
    expect(find.text('Select item'), findsNothing);
    expect(find.text('Solo Quest Remaster'), findsOneWidget);
    expect(_checked(tester, 4), isTrue);
  });

  testWidgets('double-clicking a result selects and applies it', (
    tester,
  ) async {
    await _openAndMatch(tester);
    await tester.tap(find.byKey(const Key('import-name-4')));
    await tester.pump();
    await tester.tap(find.text('Solo Quest Remaster'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Solo Quest Remaster'));
    await _settle(tester);
    expect(find.text('Select item'), findsNothing);
    expect(find.text('Solo Quest Remaster'), findsOneWidget);
  });

  testWidgets('Cancel in the picker returns to the list unchanged', (
    tester,
  ) async {
    await _openAndMatch(tester);
    await tester.tap(find.byKey(const Key('import-name-4')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('import-pick-cancel')));
    await _settle(tester);
    expect(find.text('Select games to import'), findsOneWidget);
    expect(find.text('Solo Quest Remake'), findsOneWidget);
    expect(_checked(tester, 4), isFalse);
  });

  testWidgets('In library rows are disabled and never added', (tester) async {
    final h = await _openAndMatch(
      tester,
      games: [core.Game(id: 'g1', title: 'Owned', vndbId: 'v99')],
    );
    await tester.tap(find.byKey(const Key('import-hide-imported')));
    await tester.pump();
    expect(
      tester
          .widget<Checkbox>(find.byKey(const Key('import-check-2')))
          .onChanged,
      isNull,
    );
    expect(h.repo.saves, 0);
  });

  testWidgets('a game scanned through a symlink is hidden as imported', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 980);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final temp = Directory.systemTemp.createTempSync(
      'tsumige_import_link_test_',
    );
    addTearDown(() => temp.deleteSync(recursive: true));
    final real = Directory(p.join(temp.path, 'real'))..createSync();
    _exe(real.path, 'Game/game.exe');
    final link = Link(p.join(temp.path, 'link'));
    link.createSync(real.path);
    SharedPreferences.setMockInitialValues({});
    final repo = _FakeRepository([
      core.Game(
        id: 'g1',
        title: 'Owned',
        launch: core.LaunchOverrides(
          executable: p.join(real.path, 'Game', 'game.exe'),
        ),
      ),
    ]);
    final vndb = _Vndb(const {});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
          dataDirProvider.overrideWithValue(core.DataDir(temp.path)),
          libraryRepositoryProvider.overrideWithValue(repo),
          addGameHttpClientProvider.overrideWithValue(vndb.client),
          pathPickerProvider.overrideWithValue(
            ({String? initialDirectory, PathPickMode? mode}) async => link.path,
          ),
        ],
        child: MaterialApp(
          builder: FToastBuilder(),
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: TextButton(
                  onPressed: () => showImportFolderDialog(context),
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
    await tester.pump();
    for (var i = 0;
        i < 200 && find.text('No games in this folder').evaluate().isEmpty;
        i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(find.text('No games in this folder'), findsOneWidget);
    expect(find.text('Game'), findsNothing);
    await tester.tap(find.byKey(const Key('import-hide-imported')));
    await tester.pump();
    expect(find.text('Game'), findsOneWidget);
    expect(
      tester.widget<Checkbox>(find.byKey(const Key('import-check-0'))).onChanged,
      isNull,
    );
    expect(repo.saves, 0);
  });

  testWidgets('a duplicate in the batch is hidden, and disabled when shown', (
    tester,
  ) async {
    await _openAndMatch(tester, duplicate: true, folders: 6);
    expect(find.byKey(const Key('import-check-1')), findsNothing);
    await tester.tap(find.byKey(const Key('import-hide-imported')));
    await tester.pump();
    expect(find.byKey(const Key('import-check-1')), findsOneWidget);
    expect(
      tester
          .widget<Checkbox>(find.byKey(const Key('import-check-1')))
          .onChanged,
      isNull,
    );
  });

  testWidgets('the add button saves the ticked rows with their fields', (
    tester,
  ) async {
    final h = await _openAndMatch(tester);
    await tester.tap(find.byKey(const Key('import-add')));
    await _waitForSave(tester, h.repo);
    expect(h.repo.saves, 1);
    expect(_added(h).map((g) => g.title), [
      'DEMO',
      'Rena-sensei to Pool Ryokou',
    ]);
    final demo = _added(h)[0];
    expect(demo.vndbId, 'v900017');
    expect(demo.tags, isEmpty);
    expect(demo.launch.mode, core.LaunchMode.proton);
    expect(demo.launch.executable, p.join(h.root, 'DEMO', 'DEMO.exe'));
    expect(demo.needsReview, isFalse);
    expect(demo.cover, isNotNull);
    expect(
      _added(h)[1].launch.executable,
      p.join(h.root, 'Rena sensei', 'RenaPool.exe'),
    );
    expect(find.text('Added 2 games'), findsOneWidget);
    expect(h.result, ImportFolderResult.added);
    await _drainToast(tester);
  });

  testWidgets('a matched row imports with empty own tags', (tester) async {
    final h = await _openAndMatch(tester);
    await tester.tap(find.byKey(const Key('import-add')));
    await _waitForSave(tester, h.repo);
    final demo = _added(h).firstWhere((g) => g.vndbId == 'v900017');
    expect(demo.title, 'DEMO');
    expect(demo.tags, isEmpty);
    await _drainToast(tester);
  });

  testWidgets('an unsure row that is ticked is added as needing a look', (
    tester,
  ) async {
    final h = await _openAndMatch(tester);
    await tester.tap(find.byKey(const Key('import-check-4')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('import-add')));
    await _waitForSave(tester, h.repo);
    final solo = _added(h).firstWhere((g) => g.vndbId == 'v7');
    expect(solo.title, 'Solo Quest Remake');
    expect(solo.needsReview, isTrue);
    await _drainToast(tester);
  });

  testWidgets('a cover failure is counted in the toast', (tester) async {
    final h = await _openAndMatch(
      tester,
      results: {
        ..._defaultResults(),
        'DEMO': [
          _vnRow('v900017', 'DEMO', imageUrl: 'http://127.0.0.1:9/fail.jpg'),
        ],
      },
    );
    await tester.tap(find.byKey(const Key('import-add')));
    await _waitForSave(tester, h.repo);
    expect(_added(h), hasLength(2));
    expect(find.text('Added 2 games (1 covers failed)'), findsOneWidget);
    await _drainToast(tester);
  });

  testWidgets('on macOS the folder import saves games in native mode', (
    tester,
  ) async {
    final h = await _openAndMatch(
      tester,
      platform: const HostPlatform(HostOs.macos),
    );
    await tester.tap(find.byKey(const Key('import-add')));
    await _waitForSave(tester, h.repo);
    expect(_added(h), isNotEmpty);
    expect([
      for (final g in _added(h)) g.launch.mode,
    ], everyElement(core.LaunchMode.native));
    await _drainToast(tester);
  });

  testWidgets('close is blocked while saving', (tester) async {
    final h = await _openAndMatch(tester);
    h.repo.saveGate = Completer<void>();
    await tester.tap(find.byKey(const Key('import-add')));
    for (
      var i = 0;
      i < 200 && find.text('Adding 2 of 2…').evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(find.text('Adding 2 of 2…'), findsOneWidget);
    await tester.tap(find.byKey(const Key('import-cancel')));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('Select games to import'), findsOneWidget);
    h.repo.saveGate!.complete();
    await _waitForSave(tester, h.repo);
    expect(_added(h), hasLength(2));
    await _drainToast(tester);
  });

  testWidgets('Cancel in the import dialog closes the Add dialog too', (
    tester,
  ) async {
    await _openAddDialog(tester, picked: true);
    await tester.tap(find.byKey(const Key('add-game-import')));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const Key('import-cancel')));
    await _settle(tester);
    expect(find.text('Select games to import'), findsNothing);
    expect(find.text('Choose folder…'), findsNothing);
  });

  testWidgets('a cancelled folder pick leaves the Add dialog in place', (
    tester,
  ) async {
    await _openAddDialog(tester, picked: false);
    await tester.tap(find.byKey(const Key('add-game-import')));
    await _settle(tester);
    expect(find.text('Choose folder…'), findsOneWidget);
    expect(find.text('Select games to import'), findsNothing);
  });

  testWidgets('a row still matching cannot be ticked and Add is disabled', (
    tester,
  ) async {
    final gate = Completer<void>();
    await _open(tester, gate: gate, gateQuery: 'DEMO');
    for (
      var i = 0;
      i < 200 && find.byKey(const Key('import-check-0')).evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(
      tester
          .widget<Checkbox>(find.byKey(const Key('import-check-0')))
          .onChanged,
      isNull,
    );
    await tester.pump();
    expect(
      tester.widget<BrandButton>(find.byKey(const Key('import-add'))).onPressed,
      isNull,
    );
    gate.complete();
    await _settle(tester);
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('the footer keeps its controls in view at both sizes', (
    tester,
  ) async {
    const keys = [
      'import-browse',
      'import-scan',
      'import-hide-imported',
      'import-add',
      'import-cancel',
    ];
    Finder hide() => find.byKey(const Key('import-hide-imported'));
    Finder hideBox() =>
        find.descendant(of: hide(), matching: find.byType(Checkbox));

    await _openAndMatch(tester, surface: const Size(1400, 980));
    final wide = [
      for (final key in keys) tester.getCenter(find.byKey(Key(key))).dy,
      tester.getCenter(hideBox()).dy,
    ];
    for (var i = 0; i < wide.length; i++) {
      expect(wide[i], closeTo(wide.first, 1), reason: 'control $i $wide');
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    await _openAndMatch(tester, surface: const Size(1000, 640));
    final shell = tester.getRect(find.byType(DialogShell));
    for (final key in keys) {
      final rect = tester.getRect(find.byKey(Key(key)));
      expect(shell.contains(rect.topLeft), isTrue, reason: key);
      expect(shell.contains(rect.bottomRight), isTrue, reason: key);
    }
    final add = tester.getRect(find.byKey(const Key('import-add')));
    final cancel = tester.getRect(find.byKey(const Key('import-cancel')));
    expect(cancel.right, lessThanOrEqualTo(shell.right));
    expect(add.right, lessThan(cancel.left));
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unmatched cover is an empty box with no icon', (
    tester,
  ) async {
    await _openAndMatch(tester);
    expect(find.byIcon(Icons.search_rounded), findsNothing);
  });

  testWidgets('the path column shows the start and the file name', (
    tester,
  ) async {
    await _openAndMatch(tester);
    expect(find.byType(MiddleEllipsisText), findsWidgets);
    expect(
      tester
          .widget<MiddleEllipsisText>(find.byType(MiddleEllipsisText).first)
          .text,
      endsWith('DEMO.exe'),
    );
  });

  testWidgets('the list is empty until a folder is chosen', (tester) async {
    await _open(tester, picker: Completer<String?>());
    expect(find.text('Choose a folder to import'), findsOneWidget);
    expect(find.byKey(const Key('import-check-all')), findsOneWidget);
  });

  testWidgets('nothing overflows at 1000 by 640 and 1400 by 980', (
    tester,
  ) async {
    await _openAndMatch(tester, surface: const Size(1000, 640));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('import-name-4')));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

Future<_Harness> _openAddDialog(
  WidgetTester tester, {
  required bool picked,
}) async {
  tester.view.physicalSize = const Size(1400, 980);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final temp = Directory.systemTemp.createTempSync(
    'tsumige_import_entry_test_',
  );
  addTearDown(() => temp.deleteSync(recursive: true));
  final root = _fixture(temp);
  SharedPreferences.setMockInitialValues({});
  final repo = _FakeRepository([]);
  final vndb = _Vndb(_defaultResults());
  final harness = _Harness(repo, root);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
        dataDirProvider.overrideWithValue(core.DataDir(temp.path)),
        libraryRepositoryProvider.overrideWithValue(repo),
        addGameHttpClientProvider.overrideWithValue(vndb.client),
        pathPickerProvider.overrideWithValue(
          ({String? initialDirectory, PathPickMode? mode}) async =>
              picked ? root : null,
        ),
      ],
      child: MaterialApp(
        builder: FToastBuilder(),
        home: Builder(
          builder: (context) {
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
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  expect(find.text('Choose folder…'), findsOneWidget);
  return harness;
}
