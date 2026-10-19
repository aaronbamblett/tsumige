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
import 'package:tsumige/main.dart';
import 'package:tsumige/src/constants/pref_keys.dart' as keys;
import 'package:tsumige/src/core/covers.dart' as core;
import 'package:tsumige/src/core/model.dart' as core;
import 'package:tsumige/src/core/paths.dart' as core;
import 'package:tsumige/src/core/vndb.dart' as core;
import 'package:tsumige/src/features/library/data/library_repository.dart';
import 'package:tsumige/src/features/library/domain/cover_source.dart';
import 'package:tsumige/src/features/library/domain/selection.dart';
import 'package:tsumige/src/features/library/presentation/widgets/game_cover_tile.dart';
import 'package:tsumige/src/features/library/presentation/widgets/library_toolbar.dart';
import 'package:tsumige/src/utils/prefs/app_prefs.dart';
import 'package:tsumige/src/utils/prefs/prefs_mixin.dart';
import 'package:tsumige/src/utils/theme/brand.dart';

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
  final temp = Directory.systemTemp.createTempSync('tsumige_toolbar_test_');
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
    child: const TsumigeApp(),
  ));
  await tester.pump();
  await tester.pump();
}

Finder filterBadge(WidgetTester tester, [String count = '1']) => find.descendant(
      of: find.byKey(const ValueKey('toolbar-filter')),
      matching: find.text(count),
    );

Future<void> openFilter(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('toolbar-filter')));
  await tester.pumpAndSettle();
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
  ProviderScope.containerOf(tester.element(find.byType(LibraryTopBar)))
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
  testWidgets('sort menu and Filter box show their current values',
      (tester) async {
    await pumpToolbar(tester, taggedGames());
    expect(find.text('Added'), findsOneWidget);
    expect(find.text('Filter'), findsOneWidget);
    expect(filterBadge(tester), findsNothing);
  });

  testWidgets('choosing Title sets the sort field', (tester) async {
    await pumpToolbar(tester, taggedGames());
    await tester.tap(find.text('Added'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Title').last);
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
        tester.element(find.byType(LibraryTopBar)));
    expect(container.read(sortFieldProvider), keys.SortField.title);
    expect(find.text('Title'), findsOneWidget);
  });

  testWidgets('a tag chosen in the Filter panel filters; All tags clears',
      (tester) async {
    await pumpToolbar(tester, taggedGames());
    final container = ProviderScope.containerOf(
        tester.element(find.byType(LibraryTopBar)));
    await openFilter(tester);
    await tester.tap(find.text('Romance'));
    await tester.pumpAndSettle();
    expect(container.read(tagFilterProvider), 'Romance');
    expect(filterBadge(tester), findsOneWidget);
    await tester.tap(find.text('All tags'));
    await tester.pumpAndSettle();
    expect(container.read(tagFilterProvider), isNull);
    expect(filterBadge(tester), findsNothing);
  });

  testWidgets('add is a glass brand button', (tester) async {
    await pumpToolbar(tester, taggedGames());
    expect(find.widgetWithText(BrandGlassButton, 'Add'), findsOneWidget);
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
    expect(find.textContaining(RegExp(r'\d+ games?')), findsNothing);
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

  // At 1500 wide with the pane open the left group fits before the grid's
  // edge, so the filter box ends on the last cover column. (At 1400 the
  // enlarged brand leaves less than the left group's minimum width, and it
  // clamps and runs past the grid instead — without touching Add/Settings.)
  testWidgets('Filter box ends on the last cover column at 1500 wide',
      (tester) async {
    await pumpToolbar(tester, manyGames(), size: const Size(1500, 980));
    openPane(tester, 'game-0');
    await settle(tester);
    final filterRight =
        tester.getRect(find.byKey(const ValueKey('toolbar-filter'))).right;
    expect((filterRight - lastCoverRight(tester)).abs(), lessThanOrEqualTo(1.0));
  });

  // At 1400 wide the bars merge: Add/Settings sit one gap left of the
  // window buttons instead of at the toolbar's old right edge.
  testWidgets('settings box ends one gap left of the window buttons at 1400',
      (tester) async {
    await pumpToolbar(tester, manyGames(), size: const Size(1400, 980));
    openPane(tester, 'game-0');
    await settle(tester);
    final settingsRight =
        tester.getRect(find.byKey(const ValueKey('toolbar-settings'))).right;
    expect(
      1400 - settingsRight,
      moreOrLessEquals(kWindowButtonsWidth + 10, epsilon: 1.0),
    );
  });

  testWidgets('settings box ends one gap left of the window buttons, pane closed',
      (tester) async {
    await pumpToolbar(tester, manyGames(), size: const Size(1400, 980));
    final settingsRight =
        tester.getRect(find.byKey(const ValueKey('toolbar-settings'))).right;
    expect(
      1400 - settingsRight,
      moreOrLessEquals(kWindowButtonsWidth + 10, epsilon: 1.0),
    );
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

  testWidgets('router builder passes the child through', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => tsumigeRouterBuilder(
            context,
            const SizedBox(key: ValueKey('router-child')),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('router-child')), findsOneWidget);
  });

  testWidgets('Filter panel lists user tags, then VNDB tags with counts',
      (tester) async {
    await pumpToolbar(tester, [
      core.Game(id: 'g1', title: 'Alpha', tags: ['Mine'], vndbTags: const [
        core.VndbTag(name: 'Romance', rating: 2.5, spoiler: 0, category: 'cont'),
      ]),
      core.Game(id: 'g2', title: 'Beta', vndbTags: const [
        core.VndbTag(name: 'Romance', rating: 2.0, spoiler: 0, category: 'cont'),
      ]),
      core.Game(id: 'g3', title: 'Gamma', vndbTags: const [
        core.VndbTag(name: 'Yuri', rating: 2.0, spoiler: 0, category: 'cont'),
      ]),
    ]);
    final container = ProviderScope.containerOf(
        tester.element(find.byType(LibraryTopBar)));
    await openFilter(tester);
    expect(find.text('Mine'), findsOneWidget);
    expect(find.text('VNDB tags'), findsOneWidget);
    expect(
      find.descendant(
        of: find.widgetWithText(InkWell, 'Romance'),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );
    await tester.enterText(find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'Search tags…'), 'yur');
    await tester.pumpAndSettle();
    expect(find.text('Romance'), findsNothing);
    expect(find.text('Yuri'), findsOneWidget);
    await tester.enterText(find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'Search tags…'), '');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Romance'));
    await tester.pumpAndSettle();
    expect(container.read(tagFilterProvider), 'vndb:Romance');
    expect(find.text('Gamma'), findsNothing);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
  });

  testWidgets('adult segments filter the library and count in the badge',
      (tester) async {
    await pumpToolbar(tester, [
      core.Game(id: 'g1', title: 'Alpha', adultVndb: true),
      core.Game(id: 'g2', title: 'Beta', adultVndb: false),
      core.Game(id: 'g3', title: 'Gamma', adultOverride: true),
    ]);
    final container = ProviderScope.containerOf(
        tester.element(find.byType(LibraryTopBar)));
    await openFilter(tester);
    await tester.tap(find.text('Hide adult'));
    await tester.pumpAndSettle();
    expect(container.read(adultFilterProvider), keys.AdultFilter.hide);
    expect(find.text('Alpha'), findsNothing);
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('Gamma'), findsNothing);
    expect(filterBadge(tester), findsOneWidget);
    await tester.tap(find.text('Adult only'));
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsNothing);
    expect(find.text('Gamma'), findsOneWidget);
    await tester.tap(find.text('All games'));
    await tester.pumpAndSettle();
    expect(container.read(adultFilterProvider), keys.AdultFilter.all);
    expect(filterBadge(tester), findsNothing);
  });

  testWidgets('badge counts tag, adult and developer; accent outline shows',
      (tester) async {
    await pumpToolbar(tester, taggedGames());
    final container = ProviderScope.containerOf(
        tester.element(find.byType(LibraryTopBar)));
    container.read(tagFilterProvider.notifier).set('Romance');
    container.read(adultFilterProvider.notifier).set(keys.AdultFilter.hide);
    container
        .read(developerFilterProvider.notifier)
        .set(core.Developer(id: 'p1', name: 'Azarashi Soft'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('toolbar-filter')),
        matching: find.text('3'),
      ),
      findsOneWidget,
    );
    final box = tester.widget<Container>(find
        .descendant(
          of: find.byKey(const ValueKey('toolbar-filter')),
          matching: find.byType(Container),
        )
        .first);
    final border = (box.decoration! as BoxDecoration).border! as Border;
    expect(
      border.top.color,
      Theme.of(tester.element(find.byType(LibraryTopBar))).colorScheme.primary,
    );
  });

  testWidgets('Clear all resets tag, adult and developer filters',
      (tester) async {
    await pumpToolbar(tester, taggedGames());
    final container = ProviderScope.containerOf(
        tester.element(find.byType(LibraryTopBar)));
    await openFilter(tester);
    await tester.tap(find.text('Romance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hide adult'));
    await tester.pumpAndSettle();
    container
        .read(developerFilterProvider.notifier)
        .set(core.Developer(id: 'p1', name: 'Azarashi Soft'));
    await tester.pumpAndSettle();
    expect(filterBadge(tester, '3'), findsOneWidget);
    await tester.tap(find.text('Clear all'));
    await tester.pumpAndSettle();
    expect(container.read(tagFilterProvider), isNull);
    expect(container.read(adultFilterProvider), keys.AdultFilter.all);
    expect(container.read(developerFilterProvider), isNull);
    expect(filterBadge(tester), findsNothing);
  });

  testWidgets('Escape closes the panel and returns focus to the Filter box',
      (tester) async {
    await pumpToolbar(tester, taggedGames());
    await openFilter(tester);
    expect(find.text('Adult'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Adult'), findsNothing);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'filter');
  });

  testWidgets('an outside click closes the panel without activating the tile',
      (tester) async {
    await pumpToolbar(tester, taggedGames());
    final container = ProviderScope.containerOf(
        tester.element(find.byType(LibraryTopBar)));
    await openFilter(tester);
    await tester.tap(find.text('Beta'));
    await tester.pumpAndSettle();
    expect(find.text('Adult'), findsNothing);
    expect(container.read(selectedGameIdProvider), isNull);
    expect(container.read(tagFilterProvider), isNull);
  });

  // The sort and Filter boxes are fixed at the smallest width fitting
  // their longest content (Roboto: longest sort label 82.79 px -> 200,
  // "Filter" 32.77 px + widest badge -> 141; see the constants). Every
  // sort field and the widest badge the code can show (count 3: tag +
  // adult + developer) must render with no overflow, fully inside its
  // box, and without moving either box.
  testWidgets('sort and Filter boxes fit their longest content',
      (tester) async {
    await pumpToolbar(tester, taggedGames());
    final container = ProviderScope.containerOf(
        tester.element(find.byType(LibraryTopBar)));

    double sortWidth() => tester
        .getSize(find.ancestor(
          of: find.text(sortFieldLabels[container.read(sortFieldProvider)]!),
          matching: find.byType(ToolbarBox),
        ).first)
        .width;
    final firstSortWidth = sortWidth();
    expect(firstSortWidth, moreOrLessEquals(200, epsilon: 0.5));

    for (final field in keys.SortField.values) {
      container.read(sortFieldProvider.notifier).set(field);
      await settle(tester);
      expect(tester.takeException(), isNull, reason: '$field');
      expect(sortWidth(), firstSortWidth, reason: '$field');
      final labelRect = tester.getRect(find.text(sortFieldLabels[field]!));
      final boxRect = tester.getRect(find.ancestor(
        of: find.text(sortFieldLabels[field]!),
        matching: find.byType(ToolbarBox),
      ).first);
      // The label ends before the 22 px chevron and 10 px right padding.
      expect(labelRect.right,
          lessThanOrEqualTo(boxRect.right - 32 + 1.0),
          reason: '$field');
    }

    final filterBox = find.byKey(const ValueKey('toolbar-filter'));
    expect(tester.getSize(filterBox).width, moreOrLessEquals(141, epsilon: 0.5));
    final plainWidth = tester.getSize(filterBox).width;
    container.read(tagFilterProvider.notifier).set('Romance');
    container.read(adultFilterProvider.notifier).set(keys.AdultFilter.hide);
    container
        .read(developerFilterProvider.notifier)
        .set(core.Developer(id: 'p1', name: 'Azarashi Soft'));
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(filterBadge(tester, '3'), findsOneWidget);
    // Same width with the badge on: nothing shifts when a filter turns on.
    expect(tester.getSize(filterBox).width, plainWidth);
    final badgeRect = tester.getRect(find.text('3'));
    final filterRect = tester.getRect(filterBox);
    expect(badgeRect.width, lessThanOrEqualTo(18));
    expect(badgeRect.right, lessThanOrEqualTo(filterRect.right - 10 - 22 + 1.0));
    expect(badgeRect.left, greaterThanOrEqualTo(filterRect.left + 14));
  });

  // At 1440 wide with the pane open the fitted controls hand space back to
  // search: 204.5 px before (two 180 px boxes), wider after.
  testWidgets('at 1440 wide with the pane open search is wider than before',
      (tester) async {
    await pumpToolbar(tester, manyGames(), size: const Size(1440, 900));
    openPane(tester, 'game-0');
    await settle(tester);
    expect(tester.takeException(), isNull);
    final searchWidth =
        tester.getSize(find.byKey(const ValueKey('toolbar-search'))).width;
    expect(searchWidth, greaterThan(204.5));
    expect(searchWidth, moreOrLessEquals(223.5, epsilon: 1.0));
  });

  testWidgets('toolbar does not overlap Add with the pane open and a developer set',
      (tester) async {
    for (final size in [const Size(1000, 640), const Size(1280, 800), const Size(1400, 980)]) {
      await pumpToolbar(tester, manyGames(), size: size);
      final container = ProviderScope.containerOf(
          tester.element(find.byType(LibraryTopBar)));
      container
          .read(developerFilterProvider.notifier)
          .set(core.Developer(id: 'p1', name: 'Azarashi Soft'));
      openPane(tester, 'game-0');
      await settle(tester);
      expect(tester.takeException(), isNull);
      final filterRight =
          tester.getRect(find.byKey(const ValueKey('toolbar-filter'))).right;
      final addLeft = tester.getRect(find.byTooltip('Add game')).left;
      expect(filterRight, lessThanOrEqualTo(addLeft), reason: '$size');
    }
  });
}
