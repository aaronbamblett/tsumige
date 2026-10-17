// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vnl/main.dart';
import 'package:vnl/src/constants/pref_keys.dart' as keys;
import 'package:vnl/src/core/covers.dart' as core;
import 'package:vnl/src/core/model.dart' as core;
import 'package:vnl/src/core/paths.dart' as core;
import 'package:vnl/src/core/vndb.dart' as core;
import 'package:vnl/src/features/library/data/library_repository.dart';
import 'package:vnl/src/features/library/domain/cover_source.dart';
import 'package:vnl/src/features/library/domain/selection.dart';
import 'package:vnl/src/features/library/presentation/widgets/game_cover_tile.dart';
import 'package:vnl/src/features/library/presentation/widgets/game_detail_pane.dart';
import 'package:vnl/src/features/library/presentation/widgets/library_toolbar.dart';
import 'package:vnl/src/utils/prefs/app_prefs.dart';
import 'package:vnl/src/utils/prefs/prefs_mixin.dart';
import 'package:vnl/src/widgets/desktop/desktop_window_scaffold.dart';

class ToolbarFakeRepository implements LibraryRepository {
  ToolbarFakeRepository(this.games);

  final List<core.Game> games;

  @override
  Future<core.LoadedLibrary> load() async =>
      core.LoadedLibrary(library: core.Library(games: games));

  @override
  Future<void> save(core.LoadedLibrary loaded) async {}

  @override
  Future<core.VndbRefreshReport> refreshVndbData(core.LoadedLibrary loaded) async =>
      const core.VndbRefreshReport();

  @override
  Future<core.ThumbReport> ensureThumbnails(core.Library library) async =>
      core.ThumbReport();
}

Future<void> pumpToolbar(
  WidgetTester tester,
  List<core.Game> games, {
  Size size = const Size(1280, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('window_manager'),
    (call) async {
      if (call.method == 'isMaximized') return false;
      return null;
    },
  );
  final temp = Directory.systemTemp.createTempSync('vnl_toolbar_test_');
  addTearDown(() => temp.deleteSync(recursive: true));
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider
          .overrideWithValue(await SharedPreferences.getInstance()),
      dataDirProvider.overrideWithValue(core.DataDir(temp.path)),
      libraryRepositoryProvider.overrideWithValue(
        ToolbarFakeRepository(games),
      ),
      coverExistsProvider.overrideWithValue((_) => false),
    ],
    child: const VnlApp(),
  ));
  await tester.pump();
  await tester.pump();
}

List<core.Game> taggedGames() => [
      core.Game(id: 'g1', title: 'Alpha', tags: ['Romance']),
      core.Game(id: 'g2', title: 'Beta', tags: ['Action']),
    ];

List<core.Game> manyGames() => List.generate(
      20,
      (i) => core.Game(id: 'game-$i', title: 'Game $i'),
    );

void openPane(WidgetTester tester, String id) {
  ProviderScope.containerOf(tester.element(find.byType(LibraryToolbar)))
      .read(selectedGameIdProvider.notifier)
      .select(id);
}

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

/// Right edge of the last cover in the first row.
double lastCoverRight(WidgetTester tester) {
  final tiles = find.byType(GameCoverTile);
  final firstDy = tester.getTopLeft(tiles.first).dy;
  var right = 0.0;
  for (var i = 0; i < tiles.evaluate().length; i++) {
    if ((tester.getTopLeft(tiles.at(i)).dy - firstDy).abs() < 1) {
      final cover = find.descendant(
        of: tiles.at(i),
        matching: find.byType(AspectRatio),
      );
      right = max(right, tester.getRect(cover).right);
    }
  }
  return right;
}

void main() {
  testWidgets('sort and tag menus show their current values', (tester) async {
    await pumpToolbar(tester, taggedGames());
    expect(find.text('Added'), findsOneWidget);
    expect(find.text('All tags'), findsOneWidget);
  });

  testWidgets('choosing Title sets the sort field', (tester) async {
    await pumpToolbar(tester, taggedGames());
    await tester.tap(find.text('Added'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Title').last);
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
        tester.element(find.byType(LibraryToolbar)));
    expect(container.read(sortFieldProvider), keys.SortField.title);
    expect(find.text('Title'), findsOneWidget);
  });

  testWidgets('choosing a tag filters, All tags clears', (tester) async {
    await pumpToolbar(tester, taggedGames());
    final container = ProviderScope.containerOf(
        tester.element(find.byType(LibraryToolbar)));
    await tester.tap(find.text('All tags'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Romance').last);
    await tester.pumpAndSettle();
    expect(container.read(tagFilterProvider), 'Romance');
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('toolbar-tag')),
        matching: find.text('Romance'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Romance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All tags').last);
    await tester.pump();
    expect(container.read(tagFilterProvider), isNull);
  });

  testWidgets('search is a plain hinted field with no label', (tester) async {
    await pumpToolbar(tester, taggedGames());
    expect(find.text('Search visual novels…'), findsOneWidget);
    expect(find.text('Search'), findsNothing);
    expect(find.byKey(const ValueKey('toolbar-search')), findsOneWidget);
  });

  testWidgets('toolbar has no game count and no cover slider',
      (tester) async {
    await pumpToolbar(tester, manyGames());
    expect(find.byType(Slider), findsNothing);
    expect(find.textContaining('games'), findsNothing);
    expect(find.textContaining(' of '), findsNothing);
  });

  testWidgets('pane open at 1000 wide: no overflow, search is 200 wide',
      (tester) async {
    await pumpToolbar(tester, manyGames(), size: const Size(1000, 640));
    openPane(tester, 'game-0');
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byKey(const ValueKey('toolbar-search'))).width,
      200,
    );
  });

  testWidgets('tag box ends on the last cover column at 1400 wide',
      (tester) async {
    await pumpToolbar(tester, manyGames(), size: const Size(1400, 980));
    openPane(tester, 'game-0');
    await settle(tester);
    final tagRight =
        tester.getRect(find.byKey(const ValueKey('toolbar-tag'))).right;
    expect((tagRight - lastCoverRight(tester)).abs(), lessThanOrEqualTo(1.0));
  });

  testWidgets('settings box ends on the pane edge at 1400 wide',
      (tester) async {
    await pumpToolbar(tester, manyGames(), size: const Size(1400, 980));
    openPane(tester, 'game-0');
    await settle(tester);
    final settingsRight =
        tester.getRect(find.byKey(const ValueKey('toolbar-settings'))).right;
    final paneRight = tester.getRect(find.byType(GameDetailPane)).right;
    expect((settingsRight - paneRight).abs(), lessThanOrEqualTo(1.0));
  });

  testWidgets('settings box ends 12 px from the window edge with pane closed',
      (tester) async {
    await pumpToolbar(tester, manyGames(), size: const Size(1400, 980));
    final settingsRight =
        tester.getRect(find.byKey(const ValueKey('toolbar-settings'))).right;
    expect(1400 - settingsRight, moreOrLessEquals(12, epsilon: 1.0));
  });

  testWidgets('no toolbar overflow at 480, 1280 and 1920 wide',
      (tester) async {
    await pumpToolbar(tester, taggedGames());
    for (final width in [480.0, 1280.0, 1920.0]) {
      tester.view.physicalSize = Size(width, 800);
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('window scaffold wraps the app', (tester) async {
    await pumpToolbar(tester, taggedGames());
    expect(find.byType(DesktopWindowScaffold), findsOneWidget);
    final context = tester.element(find.byType(DesktopWindowScaffold));
    expect(
      vnlRouterBuilder(context, const SizedBox()),
      isA<DesktopWindowScaffold>(),
    );
  });
}
