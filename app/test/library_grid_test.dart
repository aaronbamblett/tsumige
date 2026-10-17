// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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
import 'package:vnl/src/features/library/presentation/widgets/game_detail_pane.dart';
import 'package:vnl/src/features/library/presentation/widgets/library_grid.dart';
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
  Future<core.VndbRefreshReport> refreshVndbData(core.LoadedLibrary loaded) async =>
      const core.VndbRefreshReport();

  @override
  Future<core.ThumbReport> ensureThumbnails(core.Library library) async =>
      core.ThumbReport();
}

List<core.Game> fakeGames(int count) =>
    List.generate(count, (i) => core.Game(id: 'game-$i', title: 'Game $i'));

void setSurface(WidgetTester tester, double width, double height) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

/// Repaint boundary around the whole test app so pixel tests can capture
/// exactly what renders.
final testRepaintKey = GlobalKey();

Future<void> pumpLibrary(WidgetTester tester, List<core.Game> games) async {
  setSurface(tester, 1280, 800);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('window_manager'), (
        call,
      ) async {
        if (call.method == 'isMaximized') return false;
        return null;
      });
  final temp = Directory.systemTemp.createTempSync('vnl_grid_test_');
  addTearDown(() => temp.deleteSync(recursive: true));
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
        dataDirProvider.overrideWithValue(core.DataDir(temp.path)),
        libraryRepositoryProvider.overrideWithValue(GridFakeRepository(games)),
        coverExistsProvider.overrideWithValue((_) => false),
      ],
      child: RepaintBoundary(key: testRepaintKey, child: const VnlApp()),
    ),
  );
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

/// The scrollbar's track: the bar's right 8 px, spanning the whole grid
/// viewport (which already starts [LibraryGrid.topInset] below the toolbar).
Rect scrollbarTrackRect(WidgetTester tester) {
  final bar = tester.getRect(
    find.descendant(
      of: find.byType(LibraryGrid),
      matching: find.byType(Scrollbar),
    ),
  );
  return Rect.fromLTRB(bar.right - 8, bar.top, bar.right, bar.bottom);
}

/// The grid's scroll viewport.
Rect gridViewportRect(WidgetTester tester) => tester.getRect(
  find.descendant(
    of: find.byType(LibraryGrid),
    matching: find.byType(Viewport),
  ),
);

/// The first row of covers.
List<Rect> firstRowCovers(WidgetTester tester) {
  final tiles = find.byType(GameCoverTile);
  final firstDy = tester.getTopLeft(tiles.first).dy;
  final covers = <Rect>[];
  for (var i = 0; i < tiles.evaluate().length; i++) {
    if ((tester.getTopLeft(tiles.at(i)).dy - firstDy).abs() < 1) {
      covers.add(
        tester.getRect(
          find.descendant(of: tiles.at(i), matching: find.byType(AspectRatio)),
        ),
      );
    }
  }
  return covers;
}

void main() {
  Finder findToolbarSearch() => find.descendant(
    of: find.byKey(const ValueKey('toolbar-search')),
    matching: find.byType(TextField),
  );

  testWidgets('grid builds lazily', (tester) async {
    await pumpLibrary(tester, fakeGames(2000));
    expect(find.byType(GameCoverTile).evaluate().length, lessThan(200));
  });

  testWidgets('typing in search narrows the grid', (tester) async {
    await pumpLibrary(tester, fakeGames(20));
    await tester.enterText(findToolbarSearch(), 'Game 7');
    await tester.pump();
    expect(find.byType(GameCoverTile), findsOneWidget);
    expect(find.textContaining(RegExp(r'\d+ games?')), findsNothing);
  });

  testWidgets('a wider cover setting lowers the column count', (tester) async {
    await pumpLibrary(tester, fakeGames(2000));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(LibraryGrid)),
    );
    final before = firstRowColumns(tester);
    expect(before, greaterThan(1));
    container.read(coverWidthProvider.notifier).set(400);
    await tester.pump();
    await tester.pump();
    expect(firstRowColumns(tester), lessThan(before));
  });

  testWidgets('toolbar is one row at 1280 wide', (tester) async {
    await pumpLibrary(tester, fakeGames(20));
    final items = [
      findToolbarSearch(),
      find.byType(MenuAnchor).at(0),
      find.byTooltip('Ascending'),
      find.text('Favourites'),
      find.byKey(const ValueKey('toolbar-filter')),
      find.byTooltip('Add game'),
      find.byTooltip('Settings'),
    ];
    for (final item in items) {
      expect(item, findsOneWidget);
    }
    final centres = [for (final item in items) tester.getCenter(item).dy];
    final spread = centres.reduce(max) - centres.reduce(min);
    expect(spread, lessThanOrEqualTo(1.0));
  });

  testWidgets('every cover has the same height at any slider value', (
    tester,
  ) async {
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
    final container = ProviderScope.containerOf(
      tester.element(find.byType(LibraryGrid)),
    );
    for (final width in [100, 192, 400]) {
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
      expect(heights.reduce(max) - heights.reduce(min), lessThanOrEqualTo(0.5));
      for (final rect in rects) {
        expect(
          rect.height,
          moreOrLessEquals(rect.width / kGameCoverAspectRatio, epsilon: 0.5),
        );
      }
    }
  });

  testWidgets('tile is exactly the cover plus the title block', (tester) async {
    await pumpLibrary(tester, fakeGames(6));
    final block = gameTitleBlockHeight(
      tester.element(find.byType(GameCoverTile).first),
    );
    final tileRect = tester.getRect(find.byType(GameCoverTile).first);
    final coverRect = tester.getRect(
      find.byKey(const ValueKey('cover-game-0')),
    );
    expect(
      coverRect.height,
      moreOrLessEquals(coverRect.width / kGameCoverAspectRatio, epsilon: 0.5),
    );
    expect(
      tileRect.height,
      moreOrLessEquals(coverRect.height + block, epsilon: 0.5),
    );
    expect(
      tileRect.bottom - coverRect.bottom,
      moreOrLessEquals(block, epsilon: 0.5),
    );
  });

  testWidgets('title sits below the cover', (tester) async {
    await pumpLibrary(tester, [core.Game(id: 'g1', title: 'Alpha Title')]);
    final coverRect = tester.getRect(find.byKey(const ValueKey('cover-g1')));
    final titleRect = tester.getRect(find.text('Alpha Title'));
    expect(titleRect.top, greaterThanOrEqualTo(coverRect.bottom - 0.5));
    expect(titleRect.left, moreOrLessEquals(coverRect.left, epsilon: 0.5));
    expect(titleRect.right, lessThanOrEqualTo(coverRect.right + 0.5));
  });

  testWidgets('scrollbar track lines up with the covers and the pane', (
    tester,
  ) async {
    await pumpLibrary(tester, fakeGames(20));
    await tester.tap(find.text('Game 0'));
    await tester.pump();
    await tester.pump();
    final track = scrollbarTrackRect(tester);
    final firstCover = tester.getRect(
      find.byKey(const ValueKey('cover-game-0')),
    );
    final pane = tester.getRect(find.byType(GameDetailPane));
    expect((track.top - firstCover.top).abs(), lessThanOrEqualTo(1.0));
    expect((track.top - pane.top).abs(), lessThanOrEqualTo(1.0));
  });

  testWidgets('first covers start at the viewport top, level with the pane', (
    tester,
  ) async {
    await pumpLibrary(tester, fakeGames(20));
    // Pane closed: no top padding inside the viewport.
    var firstCover = tester.getRect(find.byKey(const ValueKey('cover-game-0')));
    expect(
      (firstCover.top - gridViewportRect(tester).top).abs(),
      lessThanOrEqualTo(1.0),
    );
    // Pane open: the first row lines up with the pane top.
    await tester.tap(find.text('Game 0'));
    await tester.pump();
    await tester.pump();
    firstCover = tester.getRect(find.byKey(const ValueKey('cover-game-0')));
    final pane = tester.getRect(find.byType(GameDetailPane));
    expect((firstCover.top - pane.top).abs(), lessThanOrEqualTo(1.0));
  });

  testWidgets('scrolled covers clip at the pane top line', (tester) async {
    await pumpLibrary(tester, fakeGames(2000));
    await tester.tap(find.text('Game 0'));
    await tester.pump();
    await tester.pump();
    final pane = tester.getRect(find.byType(GameDetailPane));
    expect(
      (gridViewportRect(tester).top - pane.top).abs(),
      lessThanOrEqualTo(1.0),
    );
    await tester.drag(
      find.byKey(const ValueKey('cover-game-0')),
      const Offset(0, -300),
    );
    await tester.pump();
    await tester.pump();
    final grid = tester.getRect(find.byType(LibraryGrid));
    final track = scrollbarTrackRect(tester);
    final boundary =
        testRepaintKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final (image, bytes) = await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return (image, data!);
    }) as (ui.Image, ByteData);
    final top = (pane.top - LibraryGrid.topInset).round();
    final bottom = pane.top.round() - 1;
    final left = grid.left.round();
    final right = track.left.round();
    expect(bottom - top, greaterThanOrEqualTo(8));
    int pixelAt(int x, int y) => bytes.getUint32((y * image.width + x) * 4);
    final background = pixelAt(left, top);
    var different = 0;
    for (var y = top; y <= bottom; y++) {
      for (var x = left; x < right; x++) {
        if (pixelAt(x, y) != background) different++;
      }
    }
    expect(
      different,
      0,
      reason: 'covers render in the band above the viewport top',
    );
  });

  testWidgets('scrollbar track top sits on the pane top line', (tester) async {
    await pumpLibrary(tester, fakeGames(20));
    await tester.tap(find.text('Game 0'));
    await tester.pump();
    await tester.pump();
    final track = scrollbarTrackRect(tester);
    final pane = tester.getRect(find.byType(GameDetailPane));
    expect((track.top - pane.top).abs(), lessThanOrEqualTo(1.0));
  });

  testWidgets('scrollbar keeps its distance from the covers and the pane', (
    tester,
  ) async {
    await pumpLibrary(tester, fakeGames(20));
    // Pane closed: the scrollbar sits flush with the window edge.
    var track = scrollbarTrackRect(tester);
    expect(1280 - track.right, moreOrLessEquals(0, epsilon: 1.0));
    // Last cover column to scrollbar: at least 8 px.
    final rightmost = firstRowCovers(tester)
        .map((rect) => rect.right)
        .reduce(max);
    expect(track.left - rightmost, greaterThanOrEqualTo(8.0));
    // Pane open: at least 12 px between scrollbar and pane.
    await tester.tap(find.text('Game 0'));
    await tester.pump();
    await tester.pump();
    track = scrollbarTrackRect(tester);
    final pane = tester.getRect(find.byType(GameDetailPane));
    expect(pane.left - track.right, greaterThanOrEqualTo(12.0));
  });

  testWidgets('neighbouring covers are spaced 20px apart', (tester) async {
    await pumpLibrary(tester, fakeGames(20));
    final tiles = find.byType(GameCoverTile);
    final firstDy = tester.getTopLeft(tiles.first).dy;
    final row = <Rect>[];
    for (var i = 0; i < tiles.evaluate().length; i++) {
      if ((tester.getTopLeft(tiles.at(i)).dy - firstDy).abs() < 1) {
        final cover = find.descendant(
          of: tiles.at(i),
          matching: find.byType(AspectRatio),
        );
        row.add(tester.getRect(cover));
      }
    }
    expect(row.length, greaterThan(1));
    row.sort((a, b) => a.left.compareTo(b.left));
    for (var i = 1; i < row.length; i++) {
      expect(
        row[i].left - row[i - 1].right,
        moreOrLessEquals(20.0, epsilon: 0.5),
      );
    }
  });

  testWidgets('tags do not appear on tiles', (tester) async {
    await pumpLibrary(tester, [
      core.Game(id: 'g1', title: 'Alpha', tags: ['zzz-unique-tag']),
    ]);
    expect(
      find.descendant(
        of: find.byType(GameCoverTile),
        matching: find.textContaining('zzz-unique-tag'),
      ),
      findsNothing,
    );
  });

  testWidgets('no overflow at slider values 100, 192 and 400', (tester) async {
    await pumpLibrary(tester, fakeGames(8));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(LibraryGrid)),
    );
    for (final width in [100, 192, 400]) {
      container.read(coverWidthProvider.notifier).set(width);
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('cover source follows the settled width', (tester) async {
    await pumpLibrary(tester, fakeGames(2000));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(LibraryGrid)),
    );
    expect(container.read(coverWidthProvider), 192);

    container.read(coverWidthProvider.notifier).set(300);
    await tester.pump();
    expect(container.read(settledCoverWidthProvider), 192);

    await tester.pump(const Duration(milliseconds: 300));
    expect(container.read(settledCoverWidthProvider), 300);
  });

  testWidgets('tiles show no VNDB Rating text', (tester) async {
    await pumpLibrary(tester, [
      core.Game(id: 'g1', title: 'Alpha', vndbRating: 75.0),
    ]);
    expect(find.textContaining('VNDB Rating'), findsNothing);
  });

  testWidgets('tapping the selected tile closes the pane', (tester) async {
    await pumpLibrary(tester, fakeGames(20));
    await tester.tap(find.text('Game 0'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(GameDetailPane), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cover-game-0')));
    await tester.pump();
    await tester.pump();
    expect(find.byType(GameDetailPane), findsNothing);
  });

  testWidgets('tapping empty grid space closes the pane', (tester) async {
    await pumpLibrary(tester, fakeGames(20));
    await tester.tap(find.text('Game 0'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(GameDetailPane), findsOneWidget);
    final viewport = gridViewportRect(tester);
    await tester.tapAt(Offset(viewport.left + 5, viewport.top + 100));
    await tester.pump();
    await tester.pump();
    expect(find.byType(GameDetailPane), findsNothing);
  });

  testWidgets('an empty result shows a message in the grid', (tester) async {
    await pumpLibrary(tester, fakeGames(20));
    await tester.enterText(findToolbarSearch(), 'zzz');
    await tester.pump();
    expect(find.text('No games match'), findsOneWidget);
    expect(find.byType(GameCoverTile), findsNothing);
  });

  testWidgets('scrollbars are always visible, thin and app-coloured', (
    tester,
  ) async {
    await pumpLibrary(tester, fakeGames(20));
    final context = tester.element(find.byType(LibraryGrid));
    final theme = Theme.of(context).scrollbarTheme;
    expect(theme.thumbVisibility?.resolve({}), isTrue);
    expect(theme.thickness?.resolve({}), 8);
    expect(theme.radius, const Radius.circular(4));
    final bar = tester.widget<Scrollbar>(
      find.descendant(
        of: find.byType(LibraryGrid),
        matching: find.byType(Scrollbar),
      ),
    );
    expect(bar.thumbVisibility, isTrue);
  });
}
