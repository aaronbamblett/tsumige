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
import 'package:vnl/src/core/covers.dart' as core;
import 'package:vnl/src/core/model.dart' as core;
import 'package:vnl/src/core/paths.dart' as core;
import 'package:vnl/src/core/vndb.dart' as core;
import 'package:vnl/src/features/library/data/library_repository.dart';
import 'package:vnl/src/features/library/domain/add_game.dart';
import 'package:vnl/src/features/library/domain/game_editor.dart';
import 'package:vnl/src/features/library/presentation/add_game/add_game_dialog.dart';
import 'package:vnl/src/features/library/presentation/add_game/import_folder_dialog.dart';
import 'package:vnl/src/utils/prefs/prefs_mixin.dart';

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
  _Vndb(this.byQuery);

  final Map<String, List<Map<String, Object?>>> byQuery;

  MockClient get client => MockClient((request) async {
    if (request.method == 'POST') {
      final body = jsonDecode(request.body) as Map;
      final filters = body['filters'] as List;
      if (filters.first == 'search') {
        final query = filters[2] as String;
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
};

void _exe(String root, String relative) {
  final file = File(p.join(root, relative));
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync([0, 1, 2]);
}

/// Root "Visual novels" with five subfolders:
///  DEMO          exact match, pre-ticked
///  Nothing Here  no exe, no match
///  Owned Game    matches a library game, disabled
///  Rena sensei   close match, pre-ticked
///  Solo Quest    two results (check match), two exes
String _fixture(Directory temp) {
  final root = p.join(temp.path, 'Visual novels');
  _exe(root, 'DEMO/DEMO.exe');
  _exe(root, 'DEMO/unins000.exe');
  _exe(root, 'Nothing Here/notes.txt');
  _exe(root, 'Owned Game/Owned.exe');
  _exe(root, 'Rena sensei/RenaPool.exe');
  _exe(root, 'Solo Quest/Solo.exe');
  _exe(root, 'Solo Quest/bin/Extra.exe');
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
}) async {
  tester.view.physicalSize = surface;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final temp = Directory.systemTemp.createTempSync('vnl_import_dialog_test_');
  addTearDown(() => temp.deleteSync(recursive: true));
  final root = _fixture(temp);
  SharedPreferences.setMockInitialValues({});
  final repo = _FakeRepository([
    ...(games ?? [_ownedGame()]),
  ]);
  final vndb = _Vndb(results ?? _defaultResults());
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
          ({String? initialDirectory, PathPickMode? mode}) async => root,
        ),
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
}) async {
  final harness = await _open(
    tester,
    games: games,
    results: results,
    surface: surface,
  );
  for (var i = 0; i < 200; i++) {
    final done =
        find.textContaining('5 folders · ').evaluate().isNotEmpty &&
        find.text('Matching…').evaluate().isEmpty;
    if (done) break;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
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
  testWidgets('rows show their match state, pre-ticks and counts', (
    tester,
  ) async {
    await _openAndMatch(
      tester,
      games: [core.Game(id: 'g1', title: 'Owned', vndbId: 'v99')],
    );
    expect(find.text('Import a folder'), findsOneWidget);
    expect(find.text('Add games'), findsOneWidget);
    expect(find.text('5 folders · 2 selected'), findsOneWidget);
    expect(find.text('Matched'), findsNWidgets(2));
    expect(find.text('Check match'), findsOneWidget);
    expect(find.text('No match'), findsOneWidget);
    expect(find.text('In library'), findsOneWidget);
    expect(find.text('No VNDB match'), findsOneWidget);
    expect(find.text('Find'), findsOneWidget);
    expect(find.text("Pick the game's .exe"), findsOneWidget);
    expect(find.text('Solo Quest Remake'), findsOneWidget);
    expect(_checked(tester, 0), isTrue);
    expect(_checked(tester, 1), isFalse);
    expect(_checked(tester, 3), isTrue);
    expect(_checked(tester, 4), isFalse);
  });

  testWidgets('In library rows are disabled and never added', (tester) async {
    final h = await _openAndMatch(
      tester,
      games: [core.Game(id: 'g1', title: 'Owned', vndbId: 'v99')],
    );
    expect(
      tester
          .widget<Checkbox>(find.byKey(const Key('import-check-2')))
          .onChanged,
      isNull,
    );
    await tester.tap(find.byKey(const Key('import-check-2')));
    await tester.pump();
    expect(find.text('5 folders · 2 selected'), findsOneWidget);
    expect(h.repo.saves, 0);
  });

  testWidgets('Change picks a result and the list shows it ticked', (
    tester,
  ) async {
    await _openAndMatch(tester);
    await tester.tap(find.byKey(const Key('import-change-4')));
    await tester.pump();
    expect(find.text('Pick the VNDB entry'), findsOneWidget);
    expect(find.text('Import a folder · Solo Quest'), findsOneWidget);
    expect(
      find.text('Search by title, or paste a VNDB id or link (v12345).'),
      findsOneWidget,
    );
    expect(find.text('Current match'), findsOneWidget);
    await tester.tap(find.text('Solo Quest Remaster'));
    await _settle(tester);
    expect(find.text('Pick the VNDB entry'), findsNothing);
    expect(find.text('Solo Quest Remaster'), findsOneWidget);
    expect(find.text('5 folders · 3 selected'), findsOneWidget);
    expect(_checked(tester, 4), isTrue);
  });

  testWidgets('Use folder name, no VNDB keeps the exe and ticks the row', (
    tester,
  ) async {
    await _openAndMatch(tester);
    await tester.tap(find.byKey(const Key('import-change-4')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('import-pick-plain')));
    await _settle(tester);
    expect(find.text('Pick the VNDB entry'), findsNothing);
    expect(find.text('No VNDB'), findsOneWidget);
    expect(_checked(tester, 4), isTrue);
  });

  testWidgets('the exe dropdown changes the exe', (tester) async {
    await _openAndMatch(tester);
    await tester.tap(find.byKey(const Key('import-exe-4')));
    await tester.pump();
    await tester.tap(find.text('bin/Extra.exe').last);
    await _settle(tester);
    expect(
      find.descendant(
        of: find.byKey(const Key('import-exe-4')),
        matching: find.text('bin/Extra.exe'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the tag chip toggles the folder tag off for the batch', (
    tester,
  ) async {
    final h = await _openAndMatch(tester);
    expect(find.text('Visual novels'), findsOneWidget);
    await tester.tap(find.byKey(const Key('import-tag-chip')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('import-add')));
    await _waitForSave(tester, h.repo);
    expect(_added(h), hasLength(2));
    expect([for (final g in _added(h)) g.tags], [[], []]);
    await _drainToast(tester);
  });

  testWidgets('Add saves the ticked rows once with the right fields', (
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
    expect(demo.tags, ['Visual novels']);
    expect(demo.launch.mode, core.LaunchMode.proton);
    expect(demo.launch.executable, p.join(h.root, 'DEMO', 'DEMO.exe'));
    expect(demo.cover, isNotNull);
    expect(
      _added(h)[1].launch.executable,
      p.join(h.root, 'Rena sensei', 'RenaPool.exe'),
    );
    expect(find.text('Added 2 games'), findsOneWidget);
    expect(h.result, ImportFolderResult.added);
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
    expect(find.text('Import a folder'), findsOneWidget);
    h.repo.saveGate!.complete();
    await _waitForSave(tester, h.repo);
    expect(_added(h), hasLength(2));
    await _drainToast(tester);
  });

  testWidgets('the Add dialog offers Import a folder and Back returns to it', (
    tester,
  ) async {
    final entry = await _openAddDialog(tester, picked: true);
    await tester.tap(find.byKey(const Key('add-game-import')));
    await tester.pump();
    await tester.pump();
    expect(find.text('Import a folder'), findsOneWidget);
    await tester.tap(find.byKey(const Key('import-back')));
    await _settle(tester);
    expect(find.text('Find on VNDB'), findsOneWidget);
    expect(find.text('Import a folder'), findsNothing);
    expect(entry.result, isNull);
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
    expect(find.text('Import a folder'), findsNothing);
    expect(find.text('Find on VNDB'), findsNothing);
  });

  testWidgets('a cancelled folder pick leaves the Add dialog in place', (
    tester,
  ) async {
    await _openAddDialog(tester, picked: false);
    await tester.tap(find.byKey(const Key('add-game-import')));
    await _settle(tester);
    expect(find.text('Find on VNDB'), findsOneWidget);
    expect(find.text('Import a folder'), findsNothing);
  });

  for (final size in const [Size(1400, 980), Size(1000, 640)]) {
    testWidgets(
      'nothing overflows at ${size.width.toInt()} by ${size.height.toInt()}',
      (tester) async {
        await _openAndMatch(tester, surface: size);
        expect(find.text('5 folders · 2 selected'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
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
  final temp = Directory.systemTemp.createTempSync('vnl_import_entry_test_');
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
  expect(find.text('Find on VNDB'), findsOneWidget);
  return harness;
}
