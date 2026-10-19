// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tsumige/main.dart';
import 'package:tsumige/src/core/covers.dart' as covers;
import 'package:tsumige/src/core/host_platform.dart';
import 'package:tsumige/src/core/model.dart' as core;
import 'package:tsumige/src/core/paths.dart' as paths;
import 'package:tsumige/src/core/vndb.dart' as vndb;
import 'package:tsumige/src/features/library/data/library_repository.dart';
import 'package:tsumige/src/features/library/domain/cover_source.dart';
import 'package:tsumige/src/features/library/presentation/widgets/library_grid.dart';
import 'package:tsumige/src/features/library/presentation/widgets/library_toolbar.dart';
import 'package:tsumige/src/routes/router.dart';
import 'package:tsumige/src/utils/prefs/prefs_mixin.dart';
import 'package:tsumige/src/utils/platform/platform_runtime.dart';
import 'package:tsumige/src/widgets/desktop/desktop_title_bar.dart';
import 'package:tsumige/src/widgets/desktop/desktop_window_scaffold.dart';
import 'package:tsumige/src/widgets/tsumige_logo.dart';

class _FakeRepository implements LibraryRepository {
  _FakeRepository(this.games);

  final List<core.Game> games;

  @override
  Future<core.LoadedLibrary> load() async =>
      core.LoadedLibrary(library: core.Library(games: games));

  @override
  Future<void> save(core.LoadedLibrary loaded) async {}

  @override
  Future<vndb.VndbRefreshReport> refreshVndbData(
    core.LoadedLibrary loaded,
  ) =>
      Future.value(const vndb.VndbRefreshReport());

  @override
  Future<covers.ThumbReport> ensureThumbnails(core.Library library) =>
      Future.value(covers.ThumbReport());
}

Future<void> _pumpApp(
  WidgetTester tester,
  List<core.Game> games, {
  required Size size,
  HostPlatform? platform,
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
  final temp = Directory.systemTemp.createTempSync('tsumige_one_bar_test_');
  addTearDown(() => temp.deleteSync(recursive: true));
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider
          .overrideWithValue(await SharedPreferences.getInstance()),
      dataDirProvider.overrideWithValue(paths.DataDir(temp.path)),
      libraryRepositoryProvider.overrideWithValue(_FakeRepository(games)),
      coverExistsProvider.overrideWithValue((_) => false),
      if (platform != null) hostPlatformProvider.overrideWithValue(platform),
    ],
    child: const TsumigeApp(),
  ));
  await tester.pump();
  await tester.pump();
}

List<core.Game> _games() => List.generate(
      20,
      (i) => core.Game(id: 'game-$i', title: 'Game $i'),
    );

void main() {
  testWidgets('at 1280 wide the search field and window buttons share one bar',
      (tester) async {
    await _pumpApp(tester, _games(), size: const Size(1280, 800));

    // One 64 px bar: no separate 40 px title bar anywhere.
    expect(find.byType(DesktopTitleBar), findsNothing);
    expect(find.byType(LibraryToolbar), findsNothing);
    expect(find.byType(DesktopWindowButtons), findsOneWidget);
    expect(find.byType(DragToMoveArea), findsOneWidget);

    final searchCenter =
        tester.getCenter(find.byKey(const ValueKey('toolbar-search')));
    final buttonsCenter = tester.getCenter(find.byType(DesktopWindowButtons));
    expect(
      (searchCenter.dy - buttonsCenter.dy).abs(),
      lessThanOrEqualTo(1.0),
    );
    expect(searchCenter.dy, moreOrLessEquals(32, epsilon: 1.0));

    // The brand starts at the grid's horizontal padding.
    final logoLeft = tester.getTopLeft(find.byType(TsumigeLogo)).dx;
    expect(
      logoLeft,
      moreOrLessEquals(LibraryGrid.horizontalPadding, epsilon: 1.0),
    );

    // The grid starts below the 64 px bar.
    final gridTop = tester.getTopLeft(find.byType(LibraryGrid)).dy;
    expect(gridTop, moreOrLessEquals(64, epsilon: 1.0));
  });

  testWidgets('at 1000 wide the title bar and toolbar stack as before',
      (tester) async {
    await _pumpApp(tester, _games(), size: const Size(1000, 640));

    expect(find.byType(DesktopTitleBar), findsOneWidget);
    expect(
      tester.getSize(find.byType(DesktopTitleBar)),
      const Size(1000, 40),
    );
    expect(find.byType(LibraryToolbar), findsOneWidget);
    final toolbarTop = tester.getTopLeft(find.byType(LibraryToolbar)).dy;
    expect(toolbarTop, moreOrLessEquals(40, epsilon: 1.0));
  });

  testWidgets('macOS bar has no logo text and no custom window buttons',
      (tester) async {
    await _pumpApp(
      tester,
      _games(),
      size: const Size(1280, 800),
      platform: const HostPlatform(HostOs.macos),
    );

    expect(find.byType(DesktopTitleBar), findsNothing);
    expect(find.text('Tsumige'), findsNothing);
    expect(find.byType(DesktopWindowButtons), findsNothing);
    expect(find.byType(WindowCaptionButton), findsNothing);
    // The controls start past the traffic-lights inset.
    final searchLeft =
        tester.getTopLeft(find.byKey(const ValueKey('toolbar-search'))).dx;
    expect(
      searchLeft,
      moreOrLessEquals(kMacOSTrafficLightsInset + 20, epsilon: 1.0),
    );
  });

  testWidgets('one bar at the breakpoint, two rows one pixel below',
      (tester) async {
    await _pumpApp(tester, _games(), size: const Size(1280, 800));
    final context = tester.element(find.byType(LibraryTopBar));
    final breakpoint =
        oneBarBreakpoint(context, isMacOS: false).ceilToDouble();

    await _pumpApp(tester, _games(), size: Size(breakpoint, 800));
    expect(find.byType(DesktopTitleBar), findsNothing);
    expect(find.byType(LibraryToolbar), findsNothing);
    expect(find.byType(DesktopWindowButtons), findsOneWidget);

    await _pumpApp(
      tester,
      _games(),
      size: Size(breakpoint - 1, 800),
    );
    expect(find.byType(DesktopTitleBar), findsOneWidget);
    expect(find.byType(LibraryToolbar), findsOneWidget);
    expect(find.byType(DesktopWindowButtons), findsOneWidget);
  });

  testWidgets('scaffold title bar is off on the library route',
      (tester) async {
    await _pumpApp(tester, _games(), size: const Size(1280, 800));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(LibraryTopBar)),
    );
    expect(container.read(scaffoldTitleBarProvider), isFalse);

    expect(
      tsumigeRouterBuilder(
        tester.element(find.byType(LibraryTopBar)),
        const SizedBox(),
      ),
      isA<DesktopWindowScaffold>(),
    );
  });
}
