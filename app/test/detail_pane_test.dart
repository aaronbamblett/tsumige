// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vnl/main.dart';
import 'package:vnl/src/core/covers.dart' as core;
import 'package:vnl/src/core/format.dart';
import 'package:vnl/src/core/model.dart' as core;
import 'package:vnl/src/core/paths.dart' as core;
import 'package:vnl/src/core/launch/game_runner.dart';
import 'package:vnl/src/core/vndb.dart' as core;
import 'package:vnl/src/features/library/data/library_repository.dart';
import 'package:vnl/src/features/library/domain/cover_source.dart';
import 'package:vnl/src/features/library/domain/game_editor.dart';
import 'package:vnl/src/features/library/domain/running_games.dart';
import 'package:vnl/src/features/library/domain/selection.dart';
import 'package:vnl/src/features/library/presentation/widgets/detail_tabs/related_tab.dart';
import 'package:vnl/src/features/library/presentation/widgets/game_cover_tile.dart';
import 'package:vnl/src/features/library/presentation/widgets/game_detail_pane.dart';
import 'package:vnl/src/utils/prefs/prefs_mixin.dart';
import 'package:vnl/src/utils/theme/brand.dart';

class DetailFakeRepository implements LibraryRepository {
  DetailFakeRepository(this.games);

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

void setSurface(WidgetTester tester, double width, double height) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Future<void> pumpLibrary(WidgetTester tester, List<core.Game> games,
    {double width = 1280,
    double height = 800,
    void Function(Directory)? exposeTemp,
    Future<String?> Function()? coverPicker,
    Future<bool> Function(Uri)? urlOpener,
    bool Function(String)? exists}) async {
  setSurface(tester, width, height);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('window_manager'),
    (call) async => call.method == 'isMaximized' ? false : null,
  );
  final temp = Directory.systemTemp.createTempSync('vnl_detail_test_');
  addTearDown(() => temp.deleteSync(recursive: true));
  exposeTemp?.call(temp);
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider
          .overrideWithValue(await SharedPreferences.getInstance()),
      dataDirProvider.overrideWithValue(core.DataDir(temp.path)),
      libraryRepositoryProvider
          .overrideWithValue(DetailFakeRepository(games)),
      coverExistsProvider.overrideWithValue(exists ?? (_) => false),
      if (coverPicker != null)
        coverPickerProvider.overrideWithValue(coverPicker),
      if (urlOpener != null)
        vndbUrlOpenerProvider.overrideWithValue(urlOpener),
    ],
    child: const VnlApp(),
  ));
  await tester.pump();
  await tester.pump();
}

Finder _fileImage(String path) => find.byWidgetPredicate((w) {
      if (w is! Image) return false;
      final provider = w.image;
      final file = provider is ResizeImage ? provider.imageProvider : provider;
      return file is FileImage && file.file.path == path;
    });

Finder _paneFileImage(String path) => find.descendant(
    of: find.byType(GameDetailPane), matching: _fileImage(path));

Future<void> openPane(WidgetTester tester, String title) async {
  await tester.tap(find.text(title).first);
  await tester.pump();
  await tester.pump();
}

Finder paneText(WidgetTester tester, String text) => find.descendant(
      of: find.byType(GameDetailPane),
      matching: find.text(text),
    );

Finder tabLabel(String text) => find.descendant(
      of: find.byType(TabBar),
      matching: find.text(text),
    );

/// Real file work never finishes inside the fake-async test zone, so flows
/// that touch the filesystem run end to end inside `runAsync` (real async),
/// polling for the file effect before returning for assertions.
Future<void> runRealFlow(
    WidgetTester tester, Future<void> Function() flow, bool Function() done) async {
  await tester.runAsync(() async {
    await flow();
    for (var i = 0; i < 200 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  });
  expect(done(), isTrue);
  await tester.pumpAndSettle();
}

Finder richPaneText(WidgetTester tester, String text) => find.descendant(
      of: find.byType(GameDetailPane),
      matching: find.textContaining(text, findRichText: true),
    );

Future<void> openTab(WidgetTester tester, String text) async {
  await tester.tap(tabLabel(text));
  await tester.pumpAndSettle();
}

void _visitSpans(
    InlineSpan span, TextStyle? inherited, void Function(TextSpan, TextStyle?) fn) {
  if (span is TextSpan) {
    final current = inherited == null
        ? span.style
        : (span.style == null ? inherited : inherited.merge(span.style));
    fn(span, current);
    for (final child in span.children ?? const <InlineSpan>[]) {
      _visitSpans(child, current, fn);
    }
  }
}

TextStyle? spoilerSpanStyle(WidgetTester tester, String secret) {
  for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
    var seen = false;
    TextStyle? result;
    _visitSpans(rich.text, null, (span, style) {
      if (span.text != null && span.text!.contains(secret)) {
        seen = true;
        result = style;
      }
    });
    if (seen) return result;
  }
  return null;
}

Future<void> tapSpoilerText(WidgetTester tester, String secret) async {
  RichText? target;
  for (final element in find.byType(RichText).evaluate()) {
    _visitSpans((element.widget as RichText).text, null, (span, _) {
      if (span.text != null && span.text!.contains(secret)) {
        target = element.widget as RichText;
      }
    });
  }
  expect(target, isNotNull);
  await tester.ensureVisible(find.byWidget(target!));
  final paragraph =
      tester.renderObject<RenderParagraph>(find.byWidget(target!));
  final plain = target!.text.toPlainText();
  final start = plain.indexOf(secret);
  expect(start, greaterThanOrEqualTo(0));
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: start, extentOffset: start + 1),
  );
  expect(boxes, isNotEmpty);
  await tester.tapAt(paragraph.localToGlobal(boxes.first.toRect().center));
  await tester.pump();
}

void main() {
  Finder findToolbarSearch() => find.descendant(
        of: find.byKey(const ValueKey('toolbar-search')),
        matching: find.byType(TextField),
      );

  testWidgets('spoiler text is hidden until tapped, then shown',
      (tester) async {
    await pumpLibrary(tester, [
      core.Game(
          id: 'g1',
          title: 'Alpha',
          description: 'before [spoiler]secretwords[/spoiler] after'),
    ]);
    await openPane(tester, 'Alpha');
    final hidden = spoilerSpanStyle(tester, 'secretwords');
    expect(hidden?.backgroundColor, isNotNull);
    expect(hidden?.backgroundColor, hidden?.color);
    await tapSpoilerText(tester, 'secretwords');
    expect(find.textContaining('secretwords', findRichText: true),
        findsOneWidget);
    expect(spoilerSpanStyle(tester, 'secretwords')?.backgroundColor, isNull);
  });

  testWidgets('hero shows the title inside the hero area', (tester) async {
    await pumpLibrary(tester, [core.Game(id: 'g1', title: 'Alpha')]);
    await openPane(tester, 'Alpha');
    final heroRect =
        tester.getRect(find.byKey(const ValueKey('detail-hero')));
    final titleRect = tester.getRect(paneText(tester, 'Alpha'));
    expect(heroRect.contains(titleRect.topLeft), isTrue);
    expect(heroRect.contains(titleRect.bottomRight), isTrue);
  });

  testWidgets('hero shrinks so the pane fits a 640 px window', (tester) async {
    await pumpLibrary(tester, [core.Game(id: 'g1', title: 'Alpha')],
        width: 1000, height: 640);
    await openPane(tester, 'Alpha');
    expect(tester.takeException(), isNull);
    final heroRect =
        tester.getRect(find.byKey(const ValueKey('detail-hero')));
    expect(heroRect.height, lessThan(340));
    expect(heroRect.height, greaterThanOrEqualTo(180));
  });

  testWidgets('Play label follows the launch phase', (tester) async {
    await pumpLibrary(tester, [core.Game(id: 'g1', title: 'Alpha')]);
    await openPane(tester, 'Alpha');
    expect(find.widgetWithText(BrandButton, 'Play'), findsOneWidget);
    final container =
        ProviderScope.containerOf(tester.element(find.byType(GameDetailPane)));
    container
        .read(runningGamesProvider.notifier)
        .setPhase('g1', LaunchPhase.starting);
    await tester.pump();
    expect(find.widgetWithText(BrandButton, 'Launching…'), findsOneWidget);
    container
        .read(runningGamesProvider.notifier)
        .setPhase('g1', LaunchPhase.running);
    await tester.pump();
    expect(find.widgetWithText(BrandButton, 'Running'), findsOneWidget);
  });

  testWidgets('hero buttons are 38 px circles', (tester) async {
    await pumpLibrary(tester, [core.Game(id: 'g1', title: 'Alpha')]);
    await openPane(tester, 'Alpha');
    for (final tooltip in ['Favourite', 'More', 'Close']) {
      expect(
        find.descendant(
          of: find.byTooltip(tooltip),
          matching: find.byWidgetPredicate((w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).shape == BoxShape.circle),
        ),
        findsOneWidget,
        reason: tooltip,
      );
    }
  });

  testWidgets('pane tab bodies show a visible scrollbar', (tester) async {
    await pumpLibrary(tester, [core.Game(id: 'g1', title: 'Alpha')]);
    await openPane(tester, 'Alpha');
    final bars = tester.widgetList<Scrollbar>(find.descendant(
      of: find.byType(GameDetailPane),
      matching: find.byType(Scrollbar),
    ));
    expect(bars, isNotEmpty);
    for (final bar in bars) {
      expect(bar.thumbVisibility, isTrue);
    }
  });

  testWidgets('hero is 340 px tall with or without a cover', (tester) async {
    await pumpLibrary(tester, [core.Game(id: 'g1', title: 'Alpha')]);
    await openPane(tester, 'Alpha');
    final heroRect =
        tester.getRect(find.byKey(const ValueKey('detail-hero')));
    expect(heroRect.height, moreOrLessEquals(340, epsilon: 0.5));
  });

  testWidgets('the three tabs exist and Launch shows Mode', (tester) async {
    await pumpLibrary(tester, [core.Game(id: 'g1', title: 'Alpha')]);
    await openPane(tester, 'Alpha');
    for (final label in ['Info', 'Launch', 'History']) {
      expect(tabLabel(label), findsOneWidget);
    }
    expect(find.text('Mode'), findsNothing);
    await openTab(tester, 'Launch');
    expect(find.text('Mode'), findsOneWidget);
  });

  testWidgets('history shows Not played yet with no sessions',
      (tester) async {
    await pumpLibrary(tester, [core.Game(id: 'g1', title: 'Alpha')]);
    await openPane(tester, 'Alpha');
    await openTab(tester, 'History');
    expect(paneText(tester, 'Total'), findsOneWidget);
    expect(paneText(tester, 'Never'), findsNWidgets(2));
    expect(paneText(tester, 'Sessions'), findsNWidgets(2));
    expect(paneText(tester, 'Not played yet'), findsOneWidget);
  });

  testWidgets('history facts, short sessions and proportional bars',
      (tester) async {
    final now = DateTime.now();
    await pumpLibrary(tester, [
      core.Game(id: 'g1', title: 'Alpha', playSessions: [
        core.PlaySession(
            startedAt: now.subtract(const Duration(days: 2)),
            durationSeconds: 3600),
        core.PlaySession(startedAt: now, durationSeconds: 1800),
        core.PlaySession(
            startedAt: now.subtract(const Duration(days: 5)),
            durationSeconds: 19),
      ]),
    ]);
    await openPane(tester, 'Alpha');
    await openTab(tester, 'History');
    expect(paneText(tester, '1.5 hrs'), findsOneWidget);
    expect(paneText(tester, '3'), findsOneWidget);
    expect(paneText(tester, 'Today'), findsNWidgets(2));
    expect(paneText(tester, '<1 min'), findsOneWidget);
    expect(
        paneText(tester, formatPlayDay(now.subtract(const Duration(days: 2)), now)),
        findsOneWidget);
    double barWidth(int index) => tester
        .widget<FractionallySizedBox>(
            find.byKey(Key('session-bar-$index')))
        .widthFactor!;
    expect(barWidth(0), closeTo(0.5, 1e-9));
    expect(barWidth(1), closeTo(1.0, 1e-9));
    expect(barWidth(2), closeTo(19 / 3600, 1e-9));
  });

  testWidgets('history lists the newer session first', (tester) async {
    final older = DateTime.utc(2024, 1, 2, 10, 0);
    final newer = DateTime.utc(2024, 3, 4, 12, 30);
    await pumpLibrary(tester, [
      core.Game(id: 'g1', title: 'Alpha', playSessions: [
        core.PlaySession(startedAt: older, durationSeconds: 180),
        core.PlaySession(startedAt: newer, durationSeconds: 120),
      ]),
    ]);
    await openPane(tester, 'Alpha');
    await openTab(tester, 'History');
    final now = DateTime.now();
    final newerText = paneText(tester, formatPlayDay(newer, now));
    final olderText = paneText(tester, formatPlayDay(older, now));
    expect(newerText, findsNWidgets(2));
    expect(olderText, findsOneWidget);
    expect(tester.getTopLeft(newerText.last).dy,
        lessThan(tester.getTopLeft(olderText).dy));
  });

  testWidgets('info tab shows rating, tags and description labels',
      (tester) async {
    await pumpLibrary(tester, [
      core.Game(
        id: 'g1',
        title: 'Alpha',
        description: 'A story',
        released: '2024-05-06',
        vndbRating: 85.0,
        vndbVotecount: 12,
        tags: ['Action', 'Romance'],
      ),
    ]);
    await openPane(tester, 'Alpha');
    expect(find.text('★ 8.5'), findsOneWidget);
    expect(find.text('VNDB Rating · 12 votes'), findsOneWidget);
    expect(find.text('2024-05-06'), findsOneWidget);
    expect(paneText(tester, 'Tags'), findsOneWidget);
    expect(paneText(tester, 'Action'), findsOneWidget);
    expect(paneText(tester, 'Romance'), findsOneWidget);
    expect(paneText(tester, 'Description'), findsOneWidget);
  });

  testWidgets('fifteen tags wrap without overflow at panel width 400',
      (tester) async {
    await pumpLibrary(tester, [
      core.Game(
        id: 'g1',
        title: 'Alpha',
        tags: [
          for (var i = 0; i < 15; i++) 'Extremely long tag number $i',
        ],
      ),
    ]);
    await openPane(tester, 'Alpha');
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(paneText(tester, 'Extremely long tag number 14'),
        findsOneWidget);
  });

  testWidgets('changing the game resets the tab to Info', (tester) async {
    await pumpLibrary(tester, [
      core.Game(id: 'g1', title: 'Alpha', description: 'Alpha story'),
      core.Game(id: 'g2', title: 'Beta', description: 'Beta story'),
    ]);
    await openPane(tester, 'Alpha');
    await openTab(tester, 'Launch');
    expect(find.text('Mode'), findsOneWidget);
    await tester.tap(find.text('Beta').first);
    await tester.pump();
    await tester.pump();
    final tabContext = tester.element(find.byType(TabBar));
    expect(DefaultTabController.of(tabContext).index, 0);
    expect(find.text('Mode'), findsNothing);
    expect(find.text('Beta story'), findsOneWidget);
  });

  testWidgets('launch button is pinned below a long description',
      (tester) async {
    await pumpLibrary(tester, [
      core.Game(
          id: 'g1', title: 'Alpha', description: 'A very long tale. ' * 500),
    ]);
    await openPane(tester, 'Alpha');
    final launch = find.widgetWithText(BrandButton, 'Play');
    expect(launch, findsOneWidget);
    expect(tester.widget<BrandButton>(launch).onPressed, isNull);
    final launchRect = tester.getRect(launch);
    expect(launchRect.top, greaterThanOrEqualTo(0));
    expect(launchRect.bottom, lessThanOrEqualTo(800));
    expect(find.byTooltip('No executable set'), findsOneWidget);
  });

  testWidgets('run exe button is absent for a Native game', (tester) async {
    await pumpLibrary(tester, [
      core.Game(
          id: 'g1',
          title: 'Alpha',
          launch: core.LaunchOverrides(mode: core.LaunchMode.native)),
    ]);
    await openPane(tester, 'Alpha');
    expect(
        find.widgetWithText(BrandGlassButton, 'Run .exe inside prefix…'),
        findsNothing);
    expect(find.widgetWithText(BrandButton, 'Play'), findsOneWidget);
  });

  testWidgets('run exe button shows for a Proton game', (tester) async {
    await pumpLibrary(tester, [core.Game(id: 'g1', title: 'Alpha')]);
    await openPane(tester, 'Alpha');
    expect(find.widgetWithText(BrandGlassButton, 'Run .exe inside prefix…'),
        findsOneWidget);
  });

  testWidgets('play sits above run exe inside prefix', (tester) async {
    await pumpLibrary(tester, [core.Game(id: 'g1', title: 'Alpha')]);
    await openPane(tester, 'Alpha');
    final play = tester.getTopLeft(find.widgetWithText(BrandButton, 'Play'));
    final runExe = tester.getTopLeft(
        find.widgetWithText(BrandGlassButton, 'Run .exe inside prefix…'));
    expect(play.dy, lessThan(runExe.dy));
  });

  testWidgets('launch tab falls back to global defaults', (tester) async {
    await pumpLibrary(tester, [core.Game(id: 'g1', title: 'Alpha')]);
    await openPane(tester, 'Alpha');
    await openTab(tester, 'Launch');
    expect(find.textContaining('Proton', findRichText: true), findsOneWidget);
    expect(find.textContaining('default', findRichText: true),
        findsWidgets);
    expect(find.text('Prefix'), findsOneWidget);
    expect(find.text('Runner'), findsOneWidget);
    expect(find.textContaining('umu default', findRichText: true), findsOneWidget);
  });

  testWidgets('steam mode shows only the app id', (tester) async {
    await pumpLibrary(tester, [
      core.Game(
          id: 'g1',
          title: 'Alpha',
          launch: core.LaunchOverrides(
              mode: core.LaunchMode.steam, steamAppId: 123)),
    ]);
    await openPane(tester, 'Alpha');
    await openTab(tester, 'Launch');
    expect(find.text('Steam app id'), findsOneWidget);
    final appIdField = find.descendant(
      of: find.byKey(const Key('launch-steam-app-id')),
      matching: find.byType(TextField),
    );
    expect(tester.widget<TextField>(appIdField).controller?.text, '123');
    expect(find.text('Mode'), findsOneWidget);
    expect(find.text('Prefix'), findsNothing);
  });

  testWidgets('native mode shows only executable and arguments',
      (tester) async {
    await pumpLibrary(tester, [
      core.Game(
          id: 'g1',
          title: 'Alpha',
          launch: core.LaunchOverrides(
              mode: core.LaunchMode.native,
              executable: '/games/alpha/run.sh',
              arguments: '--full')),
    ]);
    await openPane(tester, 'Alpha');
    await openTab(tester, 'Launch');
    expect(find.text('Executable'), findsOneWidget);
    final exeField = find.descendant(
      of: find.byKey(const Key('launch-executable')),
      matching: find.byType(TextField),
    );
    expect(tester.widget<TextField>(exeField).controller?.text,
        '/games/alpha/run.sh');
    expect(find.text('Arguments'), findsOneWidget);
    final argsField = find.descendant(
      of: find.byKey(const Key('launch-arguments')),
      matching: find.byType(TextField),
    );
    expect(tester.widget<TextField>(argsField).controller?.text, '--full');
    expect(find.text('Prefix'), findsNothing);
    expect(find.text('Runner'), findsNothing);
  });

  testWidgets('long executable stays fully editable', (tester) async {
    final path =
        '/very/long/prefix/drive_c/Program Files/Visual Novels/Alpha Game/game/alpha-visual-novel-launcher.exe';
    await pumpLibrary(tester, [
      core.Game(
          id: 'g1',
          title: 'Alpha',
          launch: core.LaunchOverrides(executable: path)),
    ]);
    await openPane(tester, 'Alpha');
    await openTab(tester, 'Launch');
    final exeField = find.descendant(
      of: find.byKey(const Key('launch-executable')),
      matching: find.byType(TextField),
    );
    expect(tester.widget<TextField>(exeField).controller?.text, path);
  });

  testWidgets('tapping a tile opens the pane; Escape closes it',
      (tester) async {
    await pumpLibrary(tester, [core.Game(id: 'g1', title: 'Alpha')]);
    await tester.tap(find.text('Alpha').first);
    await tester.pump();
    await tester.pump();
    expect(find.text('Alpha'), findsNWidgets(2));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('Alpha'), findsOneWidget);
  });

  testWidgets('search field is at least 200 wide at 1280', (tester) async {
    await pumpLibrary(tester, [core.Game(id: 'g1', title: 'Alpha')]);
    final searchBox = find.byKey(const ValueKey('toolbar-search'));
    expect(tester.getSize(searchBox).width, greaterThanOrEqualTo(200));
  });

  testWidgets('toolbar has no overflow at 480 and 1920', (tester) async {
    await pumpLibrary(tester, [core.Game(id: 'g1', title: 'Alpha')],
        width: 480);
    await tester.pump();
    expect(tester.takeException(), isNull);
    setSurface(tester, 1920, 800);
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('filter hiding the selected game keeps the pane open',
      (tester) async {
    await pumpLibrary(tester, [
      core.Game(id: 'g1', title: 'Alpha'),
      core.Game(id: 'g2', title: 'Beta'),
    ]);
    await openPane(tester, 'Alpha');
    await tester.enterText(findToolbarSearch(), 'zzz');
    await tester.pump();
    expect(find.byType(GameCoverTile), findsNothing);
    expect(find.text('Alpha'), findsOneWidget);
  });

  testWidgets('close button clears the selection', (tester) async {
    await pumpLibrary(tester, [core.Game(id: 'g1', title: 'Alpha')]);
    await openPane(tester, 'Alpha');
    expect(find.text('Alpha'), findsNWidgets(2));
    await tester.tap(find.byTooltip('Close'));
    await tester.pump();
    expect(find.text('Alpha'), findsOneWidget);
  });

  testWidgets('selected tile uses the primary colour outline',
      (tester) async {
    await pumpLibrary(tester, [core.Game(id: 'g1', title: 'Alpha')]);
    await openPane(tester, 'Alpha');
    final cover = find.byKey(const ValueKey('cover-g1'));
    final frame = find.descendant(
      of: cover,
      matching: find.byWidgetPredicate(
        (w) => w is Container && w.decoration is BoxDecoration,
      ),
    );
    final decoration = (tester.widget<Container>(frame).foregroundDecoration
        as BoxDecoration);
    final border = decoration.border as Border;
    final primary = Theme.of(tester.element(cover)).colorScheme.primary;
    expect(border.top.color, primary);
    expect(border.top.width, 3);
  });

  testWidgets('rating without a votecount shows no votes fallback',
      (tester) async {
    await pumpLibrary(tester, [
      core.Game(id: 'g1', title: 'Alpha', vndbRating: 85.0),
    ]);
    await openPane(tester, 'Alpha');
    expect(find.text('VNDB Rating'), findsOneWidget);
    expect(find.text('★ 8.5'), findsOneWidget);
    expect(find.textContaining('votes'), findsNothing);
  });

  testWidgets('release shows in the meta row next to the rating',
      (tester) async {
    await pumpLibrary(tester, [
      core.Game(
        id: 'g1',
        title: 'Alpha',
        released: '2021-08-26',
        vndbRating: 60,
      ),
    ]);
    await openPane(tester, 'Alpha');
    expect(find.text('2021-08-26'), findsOneWidget);
  });

  testWidgets('release shows in the hero without a rating', (tester) async {
    await pumpLibrary(tester, [
      core.Game(id: 'g1', title: 'Alpha', released: '2021-08-26'),
    ]);
    await openPane(tester, 'Alpha');
    expect(find.text('2021-08-26'), findsOneWidget);
    expect(find.text('VNDB Rating'), findsNothing);
  });

  testWidgets('description has no expand chevron when it fits four lines',
      (tester) async {
    await pumpLibrary(tester, [
      core.Game(id: 'g1', title: 'Alpha', description: 'A short story.'),
    ]);
    await openPane(tester, 'Alpha');
    expect(find.byTooltip('Show more'), findsNothing);
  });

  testWidgets('description overflowing four lines gets the expand chevron',
      (tester) async {
    await pumpLibrary(tester, [
      core.Game(
        id: 'g1',
        title: 'Alpha',
        description: List.filled(40, 'A long sentence of story.').join(' '),
      ),
    ]);
    await openPane(tester, 'Alpha');
    expect(find.byTooltip('Show more'), findsOneWidget);
  });

  testWidgets('empty game shows description and notes placeholders',
      (tester) async {
    await pumpLibrary(tester, [core.Game(id: 'g1', title: 'Alpha')]);
    await openPane(tester, 'Alpha');
    expect(paneText(tester, 'Description'), findsOneWidget);
    expect(paneText(tester, 'No description'), findsOneWidget);
    expect(paneText(tester, 'Notes'), findsOneWidget);
    expect(paneText(tester, 'No notes'), findsOneWidget);
    expect(find.text('Tags'), findsNothing);
    expect(find.text('VNDB Rating'), findsNothing);
  });

  testWidgets('rating value divides by ten', (tester) async {
    await pumpLibrary(tester, [
      core.Game(id: 'g1', title: 'Alpha', vndbRating: 64),
    ]);
    await openPane(tester, 'Alpha');
    expect(richPaneText(tester, '6.4'), findsOneWidget);
  });

  testWidgets('removing a tag through its close saves', (tester) async {
    await pumpLibrary(tester, [
      core.Game(id: 'g1', title: 'Alpha', tags: ['Action', 'Romance']),
    ]);
    await openPane(tester, 'Alpha');
    await tester.ensureVisible(find.byTooltip('Remove Action'));
    await tester.tap(find.byTooltip('Remove Action'));
    await tester.pumpAndSettle();
    expect(paneText(tester, 'Action'), findsNothing);
    expect(paneText(tester, 'Romance'), findsOneWidget);
  });

  testWidgets('adding Mystery saves, adding mystery again does nothing',
      (tester) async {
    await pumpLibrary(tester, [
      core.Game(id: 'g1', title: 'Alpha', tags: ['Action']),
    ]);
    await openPane(tester, 'Alpha');
    await tester.ensureVisible(paneText(tester, '+'));
    await tester.tap(paneText(tester, '+'));
    await tester.pump();
    final field = find.descendant(
      of: find.byType(GameDetailPane),
      matching: find.byType(TextField),
    );
    await tester.enterText(field, 'Mystery');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(paneText(tester, 'Mystery'), findsOneWidget);
    expect(field, findsOneWidget);
    await tester.enterText(field, 'mystery');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(paneText(tester, 'Mystery'), findsOneWidget);
  });

  testWidgets('Escape in the tag field adds nothing', (tester) async {
    await pumpLibrary(tester, [
      core.Game(id: 'g1', title: 'Alpha', tags: ['Action']),
    ]);
    await openPane(tester, 'Alpha');
    await tester.ensureVisible(paneText(tester, '+'));
    await tester.tap(paneText(tester, '+'));
    await tester.pump();
    final field = find.descendant(
      of: find.byType(GameDetailPane),
      matching: find.byType(TextField),
    );
    await tester.enterText(field, 'Nope');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(field, findsNothing);
    expect(paneText(tester, 'Nope'), findsNothing);
    expect(paneText(tester, 'Action'), findsOneWidget);
  });

  testWidgets('the description edit saves on blur', (tester) async {
    await pumpLibrary(tester, [
      core.Game(id: 'g1', title: 'Alpha', description: 'old words'),
    ]);
    await openPane(tester, 'Alpha');
    await tester.tap(find.byTooltip('Edit description'));
    await tester.pump();
    await tester.enterText(
        find.descendant(
          of: find.byType(GameDetailPane),
          matching: find.byType(TextField),
        ),
        'new words');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(paneText(tester, 'new words'), findsOneWidget);
  });

  testWidgets('Escape in the description edit reverts', (tester) async {
    await pumpLibrary(tester, [
      core.Game(id: 'g1', title: 'Alpha', description: 'old words'),
    ]);
    await openPane(tester, 'Alpha');
    await tester.tap(find.byTooltip('Edit description'));
    await tester.pump();
    await tester.enterText(
        find.descendant(
          of: find.byType(GameDetailPane),
          matching: find.byType(TextField),
        ),
        'changed');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(paneText(tester, 'old words'), findsOneWidget);
  });

  testWidgets('an empty description shows No description with edit',
      (tester) async {
    await pumpLibrary(tester, [core.Game(id: 'g1', title: 'Alpha')]);
    await openPane(tester, 'Alpha');
    expect(paneText(tester, 'No description'), findsOneWidget);
    expect(find.byTooltip('Edit description'), findsOneWidget);
  });

  testWidgets('notes edit the same way as the description', (tester) async {
    await pumpLibrary(tester, [
      core.Game(id: 'g1', title: 'Alpha', notes: 'old notes'),
    ]);
    await openPane(tester, 'Alpha');
    expect(paneText(tester, 'Notes'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Edit notes'));
    await tester.tap(find.byTooltip('Edit notes'));
    await tester.pump();
    await tester.enterText(
        find.descendant(
          of: find.byType(GameDetailPane),
          matching: find.byType(TextField),
        ),
        'new notes');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(paneText(tester, 'new notes'), findsOneWidget);
  });

  testWidgets('the favourite toggle saves', (tester) async {
    final games = [core.Game(id: 'g1', title: 'Alpha')];
    await pumpLibrary(tester, games);
    await openPane(tester, 'Alpha');
    expect(find.byTooltip('Favourite'), findsOneWidget);
    await tester.tap(find.byTooltip('Favourite'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Unfavourite'), findsOneWidget);
    expect(games.single.favourite, isTrue);
  });

  testWidgets('delete asks first: Cancel does nothing', (tester) async {
    final games = [
      core.Game(id: 'g1', title: 'Alpha'),
      core.Game(id: 'g2', title: 'Beta'),
    ];
    await pumpLibrary(tester, games);
    await openPane(tester, 'Alpha');
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete game…'));
    await tester.pumpAndSettle();
    expect(find.text('Delete Alpha?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(GameDetailPane), findsOneWidget);
    expect(games, hasLength(2));
  });

  testWidgets('delete moves to trash and clears the selection',
      (tester) async {
    late Directory temp;
    final games = [
      core.Game(id: 'g1', title: 'Alpha'),
      core.Game(id: 'g2', title: 'Beta'),
    ];
    await pumpLibrary(tester, games,
        exposeTemp: (dir) => temp = dir);
    await openPane(tester, 'Alpha');
    await runRealFlow(tester, () async {
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete game…'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();
    }, () => Directory(p.join(temp.path, 'trash')).existsSync());
    expect(find.byType(GameDetailPane), findsNothing);
    expect(games, hasLength(1));
    final trash = Directory(p.join(temp.path, 'trash'));
    final folders =
        trash.listSync().whereType<Directory>().toList();
    expect(folders, hasLength(1));
    expect(
        File(p.join(folders.single.path, 'game.json')).existsSync(), isTrue);
  });

  testWidgets('the More menu offers Change art and no re-fetch', (tester) async {
    await pumpLibrary(tester, [core.Game(id: 'g1', title: 'Alpha')]);
    await openPane(tester, 'Alpha');
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    expect(find.text('Change art…'), findsOneWidget);
    expect(find.text('Change cover…'), findsNothing);
    expect(find.text('Re-fetch cover from VNDB'), findsNothing);
  });

  testWidgets('a game with a vndbId still has no re-fetch item', (tester) async {
    await pumpLibrary(tester, [
      core.Game(id: 'g1', title: 'Alpha', vndbId: 'v900017'),
    ]);
    await openPane(tester, 'Alpha');
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    expect(find.text('Change art…'), findsOneWidget);
    expect(find.text('Re-fetch cover from VNDB'), findsNothing);
  });

  testWidgets('Change art stores a picked file as the cover and thumbnails',
      (tester) async {
    late Directory temp;
    String? pickPath;
    await pumpLibrary(tester, [core.Game(id: 'g1', title: 'Alpha')],
        exposeTemp: (dir) => temp = dir,
        coverPicker: () async => pickPath);
    final bytes = Uint8List.fromList(
        img.encodePng(img.Image(width: 16, height: 16)));
    final coverFile = File(p.join(temp.path, 'picked.png'));
    coverFile.writeAsBytesSync(bytes);
    pickPath = coverFile.path;
    await openPane(tester, 'Alpha');
    final dir = core.DataDir(temp.path);
    await runRealFlow(tester, () async {
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Change art…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('From file…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pump();
    }, () => File(core.thumbPath(dir, 'g1', 512)).existsSync());
    expect(File(p.join(dir.coversOriginal.path, 'g1.png')).existsSync(),
        isTrue);
    expect(File(core.thumbPath(dir, 'g1', 256)).existsSync(), isTrue);
  });

  testWidgets('the hero draws the background file when one is set',
      (tester) async {
    late Directory temp;
    final bytes = Uint8List.fromList(
        img.encodePng(img.Image(width: 16, height: 16)));
    await pumpLibrary(tester,
        [core.Game(id: 'g1', title: 'Alpha', cover: 'g1.png', background: 'g1.png')],
        exposeTemp: (dir) {
          temp = dir;
          final bgDir = Directory(p.join(dir.path, 'covers', 'background'))
            ..createSync(recursive: true);
          File(p.join(bgDir.path, 'g1.png')).writeAsBytesSync(bytes);
        },
        exists: (path) => File(path).existsSync());
    final bgPath = p.join(temp.path, 'covers', 'background', 'g1.png');
    final coverPath = p.join(temp.path, 'covers', 'original', 'g1.png');
    await openPane(tester, 'Alpha');
    expect(_paneFileImage(bgPath), findsOneWidget);
    expect(_paneFileImage(coverPath), findsNothing);
  });

  testWidgets('a background file replaced in place is drawn again', (
    tester,
  ) async {
    late Directory temp;
    final first = img.encodeJpg(img.Image(width: 16, height: 16));
    await pumpLibrary(
      tester,
      [core.Game(id: 'g1', title: 'Alpha', cover: 'g1.png', background: 'g1.jpg')],
      exposeTemp: (dir) {
        temp = dir;
        Directory(p.join(dir.path, 'covers', 'background'))
            .createSync(recursive: true);
        File(p.join(dir.path, 'covers', 'background', 'g1.jpg'))
            .writeAsBytesSync(first);
      },
      exists: (path) => File(path).existsSync(),
    );
    final bgPath = p.join(temp.path, 'covers', 'background', 'g1.jpg');
    await openPane(tester, 'Alpha');
    final before = tester
        .widget<Image>(_paneFileImage(bgPath))
        .image;

    File(bgPath).writeAsBytesSync(
      img.encodeJpg(img.Image(width: 32, height: 24)),
    );
    ProviderScope.containerOf(
      tester.element(find.byType(GameDetailPane)),
    ).invalidate(artVersionProvider);
    await tester.tap(find.byTooltip('Favourite'));
    await tester.pump();
    await tester.pump();

    expect(tester.widget<Image>(_paneFileImage(bgPath)).image, isNot(before));
  });

  testWidgets('the hero draws the cover when no background is set',
      (tester) async {
    late Directory temp;
    await pumpLibrary(tester,
        [core.Game(id: 'g1', title: 'Alpha', cover: 'g1.png')],
        exposeTemp: (dir) => temp = dir,
        exists: (path) => File(path).existsSync());
    await openPane(tester, 'Alpha');
    expect(
        _fileImage(p.join(temp.path, 'covers', 'background', 'g1.png')),
        findsNothing);
    expect(_paneFileImage(p.join(temp.path, 'covers', 'original', 'g1.png')),
        findsOneWidget);
  });

  testWidgets('a portal cover path is rejected with a toast', (tester) async {
    await pumpLibrary(tester, [core.Game(id: 'g1', title: 'Alpha')],
        coverPicker: () async => '/run/user/1000/docs/c.png');
    await openPane(tester, 'Alpha');
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change art…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('From file…'));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Flatpak portal'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('original title shows under the title only when it differs',
      (tester) async {
    await pumpLibrary(tester, [
      core.Game(id: 'g1', title: 'Alpha', vndbOriginalTitle: 'アルファ'),
      core.Game(id: 'g2', title: 'Beta', vndbOriginalTitle: 'Beta'),
    ]);
    await openPane(tester, 'Alpha');
    expect(paneText(tester, 'アルファ'), findsOneWidget);
    await tester.tap(find.text('Beta').first);
    await tester.pump();
    await tester.pump();
    expect(paneText(tester, 'Beta'), findsOneWidget);
  });

  testWidgets('facts show only the known values', (tester) async {
    await pumpLibrary(tester, [core.Game(id: 'g1', title: 'Alpha')]);
    await openPane(tester, 'Alpha');
    expect(paneText(tester, 'Developer'), findsNothing);
    expect(paneText(tester, 'Language'), findsNothing);
    expect(paneText(tester, 'Length'), findsNothing);
    expect(paneText(tester, 'Played'), findsOneWidget);
    expect(paneText(tester, 'Never'), findsOneWidget);
  });

  testWidgets('facts show language, rounded length and its tooltip',
      (tester) async {
    await pumpLibrary(tester, [
      core.Game(
        id: 'g1',
        title: 'Alpha',
        originalLanguage: 'ja',
        lengthMinutes: 660,
        lengthVotes: 14,
      ),
    ]);
    await openPane(tester, 'Alpha');
    expect(paneText(tester, 'Japanese'), findsOneWidget);
    expect(paneText(tester, '~11 h'), findsOneWidget);
    expect(find.byTooltip('VNDB average from 14 votes'), findsOneWidget);
  });

  testWidgets('a length under an hour reads <1 h', (tester) async {
    await pumpLibrary(tester, [
      core.Game(id: 'g1', title: 'Alpha', lengthMinutes: 45),
    ]);
    await openPane(tester, 'Alpha');
    expect(paneText(tester, '<1 h'), findsOneWidget);
  });

  testWidgets('clicking a developer filters the library; the Filter panel clears it',
      (tester) async {
    await pumpLibrary(tester, [
      core.Game(
        id: 'g1',
        title: 'Alpha',
        developers: [core.Developer(id: 'p1', name: 'Azarashi Soft')],
      ),
      core.Game(
        id: 'g2',
        title: 'Beta',
        developers: [core.Developer(id: 'p2', name: 'Other Soft')],
      ),
    ]);
    await openPane(tester, 'Alpha');
    await tester.tap(paneText(tester, 'Azarashi Soft'));
    await tester.pumpAndSettle();
    expect(find.text('Beta'), findsNothing);
    expect(find.text('Alpha'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('toolbar-filter')));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Remove Azarashi Soft'), findsOneWidget);
    await tester.tap(find.byTooltip('Remove Azarashi Soft'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Remove Azarashi Soft'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Beta'), findsOneWidget);
  });

  testWidgets('VNDB tags default view hides spoiler and weak tags',
      (tester) async {
    await pumpLibrary(tester, [
      core.Game(id: 'g1', title: 'Alpha', vndbTags: const [
        core.VndbTag(name: 'Romance', rating: 2.5, spoiler: 0, category: 'cont'),
        core.VndbTag(name: 'Weak Tag', rating: 1.0, spoiler: 0, category: 'cont'),
        core.VndbTag(name: 'Secret Twist', rating: 2.5, spoiler: 1, category: 'cont'),
        core.VndbTag(name: 'Kissing', rating: 2.2, spoiler: 0, category: 'ero'),
        core.VndbTag(name: 'Zero Tag', rating: 0, spoiler: 0, category: 'tech'),
      ]),
    ]);
    await openPane(tester, 'Alpha');
    expect(paneText(tester, 'VNDB tags'), findsOneWidget);
    expect(paneText(tester, 'Content'), findsOneWidget);
    expect(paneText(tester, 'Sexual'), findsOneWidget);
    expect(paneText(tester, 'Technical'), findsNothing);
    expect(paneText(tester, 'Romance'), findsOneWidget);
    expect(paneText(tester, 'Kissing'), findsOneWidget);
    expect(paneText(tester, 'Weak Tag'), findsNothing);
    expect(paneText(tester, 'Secret Twist'), findsNothing);
    expect(paneText(tester, 'Show all 3'), findsOneWidget);
    expect(paneText(tester, 'Show spoilers'), findsOneWidget);
  });

  testWidgets('VNDB tag chips wrap inline at content width', (tester) async {
    await pumpLibrary(tester, [
      core.Game(id: 'g1', title: 'Alpha', vndbTags: const [
        core.VndbTag(name: 'Romance', rating: 2.5, spoiler: 0, category: 'cont'),
        core.VndbTag(name: 'Kissing', rating: 2.4, spoiler: 0, category: 'cont'),
      ]),
    ]);
    await openPane(tester, 'Alpha');
    final romance = tester.getRect(paneText(tester, 'Romance'));
    final kissing = tester.getRect(paneText(tester, 'Kissing'));
    expect(kissing.top, romance.top);
    final pane = tester.getRect(find.byType(GameDetailPane));
    final chip = tester.getRect(find.ancestor(
      of: paneText(tester, 'Romance'),
      matching: find.byType(InkWell),
    ).first);
    expect(chip.width, lessThan(pane.width / 2));
  });

  testWidgets('show all and show spoilers reveal tags and reset on game change',
      (tester) async {
    await pumpLibrary(tester, [
      core.Game(id: 'g1', title: 'Alpha', vndbTags: const [
        core.VndbTag(name: 'Romance', rating: 2.5, spoiler: 0, category: 'cont'),
        core.VndbTag(name: 'Weak Tag', rating: 1.0, spoiler: 0, category: 'cont'),
        core.VndbTag(name: 'Secret Twist', rating: 2.5, spoiler: 1, category: 'cont'),
      ]),
      core.Game(id: 'g2', title: 'Beta', vndbTags: const [
        core.VndbTag(name: 'Mystery', rating: 2.5, spoiler: 0, category: 'cont'),
      ]),
    ]);
    await openPane(tester, 'Alpha');
    await tester.ensureVisible(paneText(tester, 'Show all 2'));
    await tester.tap(paneText(tester, 'Show all 2'));
    await tester.pumpAndSettle();
    expect(paneText(tester, 'Weak Tag'), findsOneWidget);
    expect(paneText(tester, 'Show fewer'), findsOneWidget);
    await tester.ensureVisible(paneText(tester, 'Show spoilers'));
    await tester.tap(paneText(tester, 'Show spoilers'));
    await tester.pumpAndSettle();
    expect(paneText(tester, 'Secret Twist'), findsOneWidget);
    expect(find.byIcon(Icons.visibility_off_rounded), findsOneWidget);
    expect(paneText(tester, 'Hide spoilers'), findsOneWidget);
    await tester.tap(find.text('Beta').first);
    await tester.pumpAndSettle();
    expect(paneText(tester, 'Show all 1'), findsOneWidget);
    expect(paneText(tester, 'Show fewer'), findsNothing);
    expect(paneText(tester, 'Mystery'), findsOneWidget);
    expect(paneText(tester, 'Weak Tag'), findsNothing);
  });

  testWidgets('clicking a VNDB tag sets the Tag filter', (tester) async {
    await pumpLibrary(tester, [
      core.Game(id: 'g1', title: 'Alpha', vndbTags: const [
        core.VndbTag(name: 'Romance', rating: 2.5, spoiler: 0, category: 'cont'),
      ]),
      core.Game(id: 'g2', title: 'Beta'),
    ]);
    await openPane(tester, 'Alpha');
    await tester.ensureVisible(paneText(tester, 'Romance'));
    await tester.tap(paneText(tester, 'Romance'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('toolbar-filter')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    expect(find.text('Beta'), findsNothing);
  });

  testWidgets('related tab orders sequels and prequels first', (tester) async {
    await pumpLibrary(tester, [
      core.Game(id: 'g1', title: 'Alpha', relations: const [
        core.VnRelation(vndbId: 'v10', relation: 'ser', title: 'Series Part', official: true),
        core.VnRelation(vndbId: 'v900011', relation: 'seq', title: 'Sequel', official: true),
        core.VnRelation(vndbId: 'v12', relation: 'alt', title: 'Alt Title', official: true),
        core.VnRelation(vndbId: 'v13', relation: 'preq', title: 'Prequel', official: true),
        core.VnRelation(vndbId: 'v900014', relation: 'side', title: 'Side Story', official: true),
      ]),
    ]);
    await openPane(tester, 'Alpha');
    await openTab(tester, 'Related');
    Offset at(String title) => tester.getTopLeft(paneText(tester, title));
    expect(at('Sequel').dy, at('Prequel').dy);
    expect(at('Sequel').dx, lessThan(at('Prequel').dx));
    expect(at('Prequel').dx, lessThan(at('Series Part').dx));
    expect(at('Side Story').dy, greaterThan(at('Series Part').dy));
    expect(at('Alt Title').dy, at('Side Story').dy);
    expect(at('Alt Title').dx, greaterThan(at('Side Story').dx));
    expect(find.text('Series Part'), findsWidgets);
  });

  testWidgets('an owned relation selects its library game', (tester) async {
    await pumpLibrary(tester, [
      core.Game(id: 'g1', title: 'Alpha', relations: const [
        core.VnRelation(vndbId: 'v900011', relation: 'seq', title: 'Owned Sequel', official: true),
      ]),
      core.Game(id: 'g2', title: 'Owned Sequel', vndbId: 'v900011'),
    ]);
    await openPane(tester, 'Alpha');
    await openTab(tester, 'Related');
    await tester.ensureVisible(paneText(tester, 'Owned Sequel'));
    await tester.tap(paneText(tester, 'Owned Sequel'));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
        tester.element(find.byType(GameDetailPane)));
    expect(container.read(selectedGameIdProvider), 'g2');
  });

  testWidgets('an unowned relation opens its VNDB page through the opener',
      (tester) async {
    final opened = <Uri>[];
    await pumpLibrary(
      tester,
      [
        core.Game(id: 'g1', title: 'Alpha', relations: const [
          core.VnRelation(vndbId: 'v13', relation: 'preq', title: 'Prequel', official: true),
        ]),
      ],
      urlOpener: (uri) async {
        opened.add(uri);
        return true;
      },
    );
    await openPane(tester, 'Alpha');
    await openTab(tester, 'Related');
    expect(find.byIcon(Icons.north_east_rounded), findsOneWidget);
    await tester.ensureVisible(paneText(tester, 'Prequel'));
    await tester.tap(paneText(tester, 'Prequel'));
    await tester.pump();
    expect(opened.single.toString(), 'https://vndb.org/v13');
  });

  testWidgets('More like this lists owned games sharing content tags',
      (tester) async {
    await pumpLibrary(tester, [
      core.Game(id: 'g1', title: 'Alpha', vndbTags: const [
        core.VndbTag(name: 'Romance', rating: 2.0, spoiler: 0, category: 'cont'),
      ]),
      core.Game(id: 'g2', title: 'Beta', vndbTags: const [
        core.VndbTag(name: 'Romance', rating: 2.0, spoiler: 0, category: 'cont'),
      ]),
      core.Game(id: 'g3', title: 'Gamma'),
    ]);
    await openPane(tester, 'Alpha');
    await openTab(tester, 'Related');
    Finder body(String text) => find.descendant(
          of: find.byType(TabBarView),
          matching: find.text(text),
        );
    expect(body('More like this'), findsOneWidget);
    expect(body('Gamma'), findsNothing);
    await tester.ensureVisible(body('Beta'));
    await tester.tap(body('Beta'));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
        tester.element(find.byType(GameDetailPane)));
    expect(container.read(selectedGameIdProvider), 'g2');
  });

  testWidgets('empty related and similar sections are hidden', (tester) async {
    await pumpLibrary(tester, [core.Game(id: 'g1', title: 'Alpha')]);
    await openPane(tester, 'Alpha');
    await openTab(tester, 'Related');
    Finder body(String text) => find.descendant(
          of: find.byType(TabBarView),
          matching: find.text(text),
        );
    expect(body('Related'), findsNothing);
    expect(body('More like this'), findsNothing);
  });

  testWidgets('the More menu sets and clears the adult override',
      (tester) async {
    final games = [core.Game(id: 'g1', title: 'Alpha', adultVndb: false)];
    await pumpLibrary(tester, games);
    await openPane(tester, 'Alpha');
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    expect(find.text("Use VNDB's adult flag"), findsNothing);
    await tester.tap(find.text('Mark as adult'));
    await tester.pumpAndSettle();
    expect(games.single.adultOverride, isTrue);
    expect(games.single.isAdult, isTrue);
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark as not adult'));
    await tester.pumpAndSettle();
    expect(games.single.adultOverride, isFalse);
    expect(games.single.isAdult, isFalse);
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Use VNDB's adult flag"));
    await tester.pumpAndSettle();
    expect(games.single.adultOverride, isNull);
    expect(games.single.isAdult, isFalse);
  });
}
