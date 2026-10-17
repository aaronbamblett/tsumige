// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vnl/main.dart';
import 'package:vnl/src/core/covers.dart' as core;
import 'package:vnl/src/core/model.dart' as core;
import 'package:vnl/src/core/paths.dart' as core;
import 'package:vnl/src/core/vndb.dart' as core;
import 'package:vnl/src/features/library/data/library_repository.dart';
import 'package:vnl/src/features/library/domain/cover_source.dart';
import 'package:vnl/src/features/library/presentation/widgets/game_cover_grid_delegate.dart';
import 'package:vnl/src/features/library/presentation/widgets/game_cover_tile.dart';
import 'package:vnl/src/utils/prefs/app_prefs.dart';
import 'package:vnl/src/utils/prefs/prefs_mixin.dart';

class GridFakeRepository implements LibraryRepository {
  GridFakeRepository(this.games);

  final List<core.Game> games;

  @override
  Future<core.LoadedLibrary> load() async =>
      core.LoadedLibrary(library: core.Library(games: games));

  @override
  Future<void> save(core.LoadedLibrary loaded) async {}

  @override
  Future<core.RatingReport> refreshRatings(core.LoadedLibrary loaded) async =>
      const core.RatingReport();

  @override
  Future<core.ThumbReport> ensureThumbnails(core.Library library) async =>
      core.ThumbReport();
}

List<core.Game> fakeGames(int count) => List.generate(
      count,
      (i) => core.Game(id: 'game-$i', title: 'Game $i'),
    );

void setSurface(WidgetTester tester, double width, double height) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Future<void> pumpLibrary(WidgetTester tester, List<core.Game> games) async {
  setSurface(tester, 1280, 800);
  final temp = Directory.systemTemp.createTempSync('vnl_grid_test_');
  addTearDown(() => temp.deleteSync(recursive: true));
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider
          .overrideWithValue(await SharedPreferences.getInstance()),
      dataDirProvider.overrideWithValue(core.DataDir(temp.path)),
      libraryRepositoryProvider.overrideWithValue(GridFakeRepository(games)),
      coverExistsProvider.overrideWithValue((_) => false),
    ],
    child: const VnlApp(),
  ));
  await tester.pump();
  await tester.pump();
}

int firstRowColumns(WidgetTester tester) {
  final tiles = find.byType(GameCoverTile);
  final dys = [
    for (var i = 0; i < tiles.evaluate().length; i++)
      tester.getTopLeft(tiles.at(i)).dy,
  ];
  final first = dys.reduce(min);
  return dys.where((dy) => (dy - first).abs() < 1).length;
}

void main() {
  testWidgets('grid builds lazily', (tester) async {
    await pumpLibrary(tester, fakeGames(2000));
    expect(find.byType(GameCoverTile).evaluate().length, lessThan(200));
    expect(find.text('2000 games'), findsOneWidget);
  });

  testWidgets('typing in search changes the count text', (tester) async {
    await pumpLibrary(tester, fakeGames(2000));
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump();
    expect(find.text('0 of 2000'), findsOneWidget);
  });

  testWidgets('slider maximum lowers the column count', (tester) async {
    await pumpLibrary(tester, fakeGames(2000));
    final before = firstRowColumns(tester);
    expect(before, greaterThan(1));
    await tester.drag(find.byType(Slider), const Offset(500, 0));
    await tester.pump(const Duration(milliseconds: 300));
    expect(firstRowColumns(tester), lessThan(before));
  });

  testWidgets('toolbar is one row at 1280 wide', (tester) async {
    await pumpLibrary(tester, fakeGames(20));
    final items = [
      find.byType(TextField),
      find.text('Added'),
      find.byTooltip('Ascending'),
      find.byType(SegmentedButton<bool>),
      find.text('Tags'),
      find.byType(Slider),
      find.text('20 games'),
      find.byTooltip('Settings'),
    ];
    for (final item in items) {
      expect(item, findsOneWidget);
    }
    final centres = [
      for (final item in items) tester.getCenter(item).dy,
    ];
    final spread =
        centres.reduce(max) - centres.reduce(min);
    expect(spread, lessThanOrEqualTo(1.0));
  });

  testWidgets('slider hides below 900 wide', (tester) async {
    await pumpLibrary(tester, fakeGames(20));
    setSurface(tester, 860, 800);
    await tester.pump();
    expect(find.byType(Slider), findsNothing);
    expect(find.text('20 games'), findsOneWidget);
  });

  testWidgets('every cover has the same height at any slider value',
      (tester) async {
    const longTitle =
        'A very long game title that keeps going until it must wrap onto '
        'two full lines no matter how wide the tile gets in the grid view';
    final games = List.generate(
      12,
      (i) => i.isEven
          ? core.Game(id: 'game-$i', title: 'Up', vndbRating: 8.5)
          : core.Game(
              id: 'game-$i',
              title: '$longTitle $i',
              tags: ['tag-a', 'tag-b', 'tag-c', 'tag-d'],
            ),
    );
    await pumpLibrary(tester, games);
    setSurface(tester, 1280, 900);
    await tester.pump();
    await tester.pump();
    final container =
        ProviderScope.containerOf(tester.element(find.byType(Slider)));
    for (final width in [100, 192, 999]) {
      container.read(coverWidthProvider.notifier).set(width);
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      final rects = <Rect>[];
      for (final game in games) {
        final finder = find.byKey(ValueKey('cover-${game.id}'));
        if (finder.evaluate().isNotEmpty) rects.add(tester.getRect(finder));
      }
      expect(rects.length, greaterThan(1));
      final heights = rects.map((r) => r.height).toList();
      expect(heights.reduce(max) - heights.reduce(min),
          lessThanOrEqualTo(0.5));
      for (final rect in rects) {
        expect(rect.height,
            moreOrLessEquals(rect.width / kGameCoverAspectRatio, epsilon: 0.5));
      }
    }
  });

  testWidgets('tile is exactly the cover plus the card margin', (tester) async {
    await pumpLibrary(tester, fakeGames(6));
    final tileRect = tester.getRect(find.byType(GameCoverTile).first);
    final coverRect =
        tester.getRect(find.byKey(const ValueKey('cover-game-0')));
    expect(
      tileRect.height,
      moreOrLessEquals(
          coverRect.width / kGameCoverAspectRatio + 8.0, epsilon: 0.5),
    );
    expect(tileRect.bottom - coverRect.bottom,
        moreOrLessEquals(4.0, epsilon: 0.5));
  });

  testWidgets('title sits inside the cover rect', (tester) async {
    await pumpLibrary(tester, [core.Game(id: 'g1', title: 'Alpha Title')]);
    final coverRect = tester.getRect(find.byKey(const ValueKey('cover-g1')));
    final titleRect = tester.getRect(find.text('Alpha Title'));
    expect(titleRect.left, greaterThanOrEqualTo(coverRect.left - 0.5));
    expect(titleRect.right, lessThanOrEqualTo(coverRect.right + 0.5));
    expect(titleRect.top, greaterThanOrEqualTo(coverRect.top - 0.5));
    expect(titleRect.bottom, lessThanOrEqualTo(coverRect.bottom + 0.5));
  });

  testWidgets('rating shows inside the tile', (tester) async {
    await pumpLibrary(tester, [
      core.Game(id: 'g1', title: 'Alpha', vndbRating: 75.0),
    ]);
    final container =
        ProviderScope.containerOf(tester.element(find.byType(Slider)));
    container.read(coverWidthProvider.notifier).set(400);
    await tester.pump();
    await tester.pump();
    final coverRect = tester.getRect(find.byKey(const ValueKey('cover-g1')));
    final ratingRect = tester.getRect(find.text('VNDB Rating 7.5'));
    expect(ratingRect.left, greaterThanOrEqualTo(coverRect.left - 0.5));
    expect(ratingRect.right, lessThanOrEqualTo(coverRect.right + 0.5));
    expect(ratingRect.top, greaterThanOrEqualTo(coverRect.top - 0.5));
    expect(ratingRect.bottom, lessThanOrEqualTo(coverRect.bottom + 0.5));
  });

  testWidgets('rating never ellipsizes at small or large cover widths',
      (tester) async {
    await pumpLibrary(tester, [
      core.Game(id: 'g1', title: 'Alpha', vndbRating: 75.0),
    ]);
    final container =
        ProviderScope.containerOf(tester.element(find.byType(Slider)));
    for (final width in [100, 400]) {
      container.read(coverWidthProvider.notifier).set(width);
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      final ratings = find.textContaining('VNDB Rating');
      if (width == 400) expect(ratings, findsOneWidget);
      for (final element in ratings.evaluate()) {
        final paragraph = tester.renderObject<RenderParagraph>(
            find.byWidget(element.widget));
        expect(paragraph.didExceedMaxLines, isFalse);
      }
    }
  });

  testWidgets('tags do not appear on tiles', (tester) async {
    await pumpLibrary(tester, [
      core.Game(id: 'g1', title: 'Alpha', tags: ['zzz-unique-tag']),
    ]);
    expect(find.textContaining('zzz-unique-tag'), findsNothing);
  });

  testWidgets('no overflow at slider values 100, 192 and 999',
      (tester) async {
    await pumpLibrary(tester, fakeGames(8));
    final container =
        ProviderScope.containerOf(tester.element(find.byType(Slider)));
    for (final width in [100, 192, 999]) {
      container.read(coverWidthProvider.notifier).set(width);
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('cover source follows the settled width', (tester) async {
    await pumpLibrary(tester, fakeGames(2000));
    final container =
        ProviderScope.containerOf(tester.element(find.byType(Slider)));
    expect(container.read(coverWidthProvider), 192);

    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(Slider)));
    await gesture.moveBy(const Offset(100, 0));
    await tester.pump();
    final live = container.read(coverWidthProvider);
    expect(live, greaterThan(192));
    expect(container.read(settledCoverWidthProvider), 192);

    await tester.pump(const Duration(milliseconds: 300));
    expect(container.read(settledCoverWidthProvider), live);
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 300));
  });
}
