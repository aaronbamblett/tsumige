// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumige/src/core/covers.dart' as core;
import 'package:tsumige/src/core/model.dart' as core;
import 'package:tsumige/src/core/paths.dart' as core;
import 'package:tsumige/src/core/vndb.dart' as core;
import 'package:tsumige/src/core/host_platform.dart';
import 'package:tsumige/src/features/library/data/library_repository.dart';
import 'package:tsumige/src/features/library/domain/add_game.dart';
import 'package:tsumige/src/features/library/domain/steam_library.dart';
import 'package:tsumige/src/features/library/presentation/add_game/import_folder_dialog.dart';
import 'package:tsumige/src/utils/prefs/prefs_mixin.dart';

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
  Future<core.VndbRefreshReport> refreshVndbData(
    core.LoadedLibrary loaded,
  ) async => const core.VndbRefreshReport();

  @override
  Future<core.ThumbReport> ensureThumbnails(core.Library library) async =>
      core.ThumbReport();
}

/// Fake VNDB: release extlinks map a Steam App ID to a VN id, id filters
/// answer VN rows, search filters answer title rows.
class _Vndb {
  _Vndb({required this.bySteamId, required this.byVnId});

  final Map<int, String> bySteamId;
  final Map<String, Map<String, Object?>> byVnId;

  MockClient get client => MockClient((request) async {
    if (request.method == 'POST') {
      final body = jsonDecode(request.body) as Map;
      final filters = body['filters'] as List;
      if (request.url.path.endsWith('/release')) {
        if (filters.first == 'extlink') {
          final appId = (filters[2] as List)[1] as int;
          final vnId = bySteamId[appId];
          return http.Response(
            jsonEncode({
              'results': vnId == null
                  ? []
                  : [
                      {
                        'id': 'r$appId',
                        'title': 'Release $appId',
                        'vns': [
                          {'id': vnId},
                        ],
                      },
                    ],
              'more': false,
            }),
            200,
          );
        }
        return http.Response(jsonEncode({'results': [], 'more': false}), 200);
      }
      if (filters.first == 'id') {
        final vn = byVnId[filters[2] as String];
        return http.Response(
          jsonEncode({'results': vn == null ? [] : [vn], 'more': false}),
          200,
        );
      }
      if (filters.first == 'search') {
        return http.Response(
          jsonEncode({'results': [], 'more': false}),
          200,
        );
      }
      return http.Response(jsonEncode({'results': [], 'more': false}), 200);
    }
    return http.Response.bytes(
      img.encodePng(img.Image(width: 8, height: 8)),
      200,
    );
  });
}

Map<String, Object?> _vnRow(String id, String title) => {
  'id': id,
  'title': title,
  'titles': [],
  'released': '2020-06-19',
  'rating': 85.0,
  'votecount': 42,
  'image': {'url': 'http://127.0.0.1:9/cover.jpg', 'sexual': 0},
  'description': 'A story.',
  'developers': [
    {'name': 'Sample Studio'},
  ],
  'tags': [
    {'name': 'Romance', 'rating': 80.0, 'spoiler': 0},
  ],
};

List<InstalledSteamGame> _threeGames() => const [
  InstalledSteamGame(
    appId: 698780,
    name: 'Doki Doki Literature Club',
    installDir: '/steam/DDLC',
  ),
  InstalledSteamGame(
    appId: 1989270,
    name: 'Slay the Princess',
    installDir: '/steam/Slay',
  ),
  InstalledSteamGame(
    appId: 1096410,
    name: 'Coteries of New York',
    installDir: '/steam/Coteries',
  ),
];

_Vndb _vndb() => _Vndb(
  bySteamId: {698780: 'v21905'},
  byVnId: {
    'v21905': _vnRow('v21905', 'Doki Doki Literature Club!'),
  },
);

class _Harness {
  _Harness(this.repo);

  final _FakeRepository repo;
  ImportFolderResult? result;
}

Future<_Harness> _open(
  WidgetTester tester, {
  required Future<List<InstalledSteamGame>?> Function(HostPlatform) steamGames,
  required _Vndb vndb,
  List<core.Game> games = const [],
  Size surface = const Size(1400, 980),
}) async {
  tester.view.physicalSize = surface;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final temp = Directory.systemTemp.createTempSync('tsumige_steam_dialog_test_');
  addTearDown(() => temp.deleteSync(recursive: true));
  SharedPreferences.setMockInitialValues({});
  final repo = _FakeRepository([...games]);
  final harness = _Harness(repo);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
        dataDirProvider.overrideWithValue(core.DataDir(temp.path)),
        libraryRepositoryProvider.overrideWithValue(repo),
        addGameHttpClientProvider.overrideWithValue(vndb.client),
        importVndbGapProvider.overrideWithValue(Duration.zero),
        importVndbRetryWaitProvider.overrideWithValue(Duration.zero),
        listSteamGamesProvider.overrideWithValue(steamGames),
      ],
      child: MaterialApp(
        builder: FToastBuilder(),
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () async {
                  harness.result = await showSteamGamesDialog(context);
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

/// Opens the Steam dialog and waits for the rows and their VNDB matching:
/// the loader is instant, the pacing is overridden to zero.
Future<_Harness> _openAndMatch(
  WidgetTester tester, {
  required Future<List<InstalledSteamGame>?> Function(HostPlatform) steamGames,
  required _Vndb vndb,
  List<core.Game> games = const [],
}) async {
  final harness = await _open(
    tester,
    steamGames: steamGames,
    vndb: vndb,
    games: games,
  );
  for (var i = 0; i < 200; i++) {
    if (find.byKey(const Key('import-check-0')).evaluate().isNotEmpty) break;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  for (var i = 0; i < 200; i++) {
    if (find.text('Doki Doki Literature Club!').evaluate().isNotEmpty) break;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  for (var i = 0; i <= 3; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
  await tester.pump();
  return harness;
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
    'installed games list with VNDB titles, Steam paths and Steam ID ticks',
    (tester) async {
      final h = await _openAndMatch(
        tester,
        steamGames: (_) async => _threeGames(),
        vndb: _vndb(),
        games: [
          core.Game(
            id: 'lib',
            title: 'Coteries',
            launch: core.LaunchOverrides(
              mode: core.LaunchMode.steam,
              steamAppId: 1096410,
            ),
          ),
        ],
      );
      expect(find.text('Select Steam games'), findsOneWidget);
      // The Steam ID match keeps the Steam name on the main line, with
      // the VNDB title below it, and is ticked.
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(const Key('import-name-0')),
                matching: find.byType(Text),
              ),
            )
            .data,
        'Doki Doki Literature Club',
      );
      expect(find.text('Doki Doki Literature Club!'), findsOneWidget);
      expect(find.text('Steam'), findsWidgets);
      expect(find.textContaining('Steam ·'), findsNothing);
      expect(_checked(tester, 0), isTrue);
      // No extlink and no title match: the Steam name, unticked.
      expect(find.text('Slay the Princess'), findsOneWidget);
      expect(_checked(tester, 1), isFalse);
      // In the library by steamAppId: hidden while Hide imported is on.
      expect(find.text('Coteries of New York'), findsNothing);
      expect(find.byKey(const Key('import-check-2')), findsNothing);

      await tester.tap(find.byKey(const Key('import-add')));
      await _waitForSave(tester, h.repo);
      final added = h.repo.games.skip(1).toList();
      expect(added, hasLength(1));
      expect(added.single.vndbId, 'v21905');
      expect(added.single.launch.steamAppId, 698780);
      expect(added.single.launch.mode, core.LaunchMode.steam);
      expect(added.single.cover, isNotNull);
      await _drainToast(tester);
    },
  );

  testWidgets('Hide imported off shows the library row', (tester) async {
    await _openAndMatch(
      tester,
      steamGames: (_) async => _threeGames(),
      vndb: _vndb(),
      games: [
        core.Game(
          id: 'lib',
          title: 'Coteries',
          launch: core.LaunchOverrides(
            mode: core.LaunchMode.steam,
            steamAppId: 1096410,
          ),
        ),
      ],
    );
    await tester.tap(find.byKey(const Key('import-hide-imported')));
    await tester.pump();
    expect(find.text('Coteries of New York'), findsOneWidget);
  });

  testWidgets("Steam isn't installed reads as missing Steam", (tester) async {
    await _open(
      tester,
      steamGames: (_) async => null,
      vndb: _vndb(),
    );
    for (var i = 0; i < 200; i++) {
      if (find
          .text("Steam isn't installed on this computer.")
          .evaluate()
          .isNotEmpty) {
        break;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(
      find.text("Steam isn't installed on this computer."),
      findsOneWidget,
    );
  });

  testWidgets('no installed games reads as nothing to add', (tester) async {
    await _open(tester, steamGames: (_) async => [], vndb: _vndb());
    for (var i = 0; i < 200; i++) {
      if (find.text('No Steam games to add.').evaluate().isNotEmpty) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(find.text('No Steam games to add.'), findsOneWidget);
  });

  testWidgets('every installed game imported reads as nothing to add', (
    tester,
  ) async {
    await _open(
      tester,
      steamGames: (_) async => [
        const InstalledSteamGame(
          appId: 698780,
          name: 'Doki Doki Literature Club',
          installDir: '/steam/DDLC',
        ),
      ],
      vndb: _vndb(),
      games: [
        core.Game(
          id: 'lib',
          title: 'DDLC',
          launch: core.LaunchOverrides(
            mode: core.LaunchMode.steam,
            steamAppId: 698780,
          ),
        ),
      ],
    );
    for (var i = 0; i < 200; i++) {
      if (find.text('No Steam games to add.').evaluate().isNotEmpty) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(find.text('No Steam games to add.'), findsOneWidget);
  });
}
