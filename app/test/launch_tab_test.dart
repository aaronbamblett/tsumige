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
import 'package:vnl/main.dart';
import 'package:vnl/src/core/covers.dart' as core;
import 'package:vnl/src/core/launch/detect.dart' as detect;
import 'package:vnl/src/core/model.dart' as core;
import 'package:vnl/src/core/paths.dart' as core;
import 'package:vnl/src/core/vndb.dart' as core;
import 'package:vnl/src/features/library/data/library_repository.dart';
import 'package:vnl/src/features/library/domain/cover_source.dart';
import 'package:vnl/src/features/library/domain/game_editor.dart';
import 'package:vnl/src/features/library/domain/runner_detection.dart';
import 'package:vnl/src/features/library/presentation/widgets/detail_tabs/launch_tab.dart';
import 'package:vnl/src/features/library/presentation/widgets/library_toolbar.dart';
import 'package:vnl/src/features/settings/presentation/sections/settings_widgets.dart';
import 'package:vnl/src/utils/prefs/prefs_mixin.dart';
import 'package:vnl/src/utils/theme/brand.dart';

class LaunchFakeRepository implements LibraryRepository {
  LaunchFakeRepository(this.games);

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

Future<LaunchFakeRepository> pumpLaunch(
  WidgetTester tester,
  List<core.Game> games, {
  List<detect.WineRunner> wines = const [],
  List<detect.ProtonRunner> protons = const [],
  List<detect.SteamPrefix> prefixes = const [],
  Future<String?> Function({String? initialDirectory, PathPickMode mode})?
      pathPicker,
  List<core.LaunchMode>? launchModes,
  void Function()? onRunnerScan,
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('window_manager'),
    (call) async => call.method == 'isMaximized' ? false : null,
  );
  final temp = Directory.systemTemp.createTempSync('vnl_launch_tab_test_');
  addTearDown(() => temp.deleteSync(recursive: true));
  SharedPreferences.setMockInitialValues({});
  final fake = LaunchFakeRepository(games);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider
          .overrideWithValue(await SharedPreferences.getInstance()),
      dataDirProvider.overrideWithValue(core.DataDir(temp.path)),
      libraryRepositoryProvider.overrideWithValue(fake),
      coverExistsProvider.overrideWithValue((_) => false),
      wineRunnersProvider.overrideWith((ref) {
        onRunnerScan?.call();
        return Future.value(wines);
      }),
      if (launchModes != null)
        availableLaunchModesProvider.overrideWithValue(launchModes),
      protonRunnersProvider.overrideWith((ref) => Future.value(protons)),
      steamPrefixesProvider.overrideWith((ref) => Future.value(prefixes)),
      if (pathPicker != null)
        pathPickerProvider.overrideWithValue(pathPicker),
    ],
    child: const VnlApp(),
  ));
  await tester.pump();
  await tester.pump();
  return fake;
}

Future<void> openLaunch(WidgetTester tester, String title) async {
  await tester.tap(find.text(title).first);
  await tester.pump();
  await tester.pump();
  await tester.tap(find.descendant(
    of: find.byType(TabBar),
    matching: find.text('Launch'),
  ));
  await tester.pumpAndSettle();
}

Future<void> blur(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
  await tester.pump();
}

Future<void> openAdvanced(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('launch-advanced-toggle')));
  await tester.tap(find.byKey(const Key('launch-advanced-toggle')));
  await tester.pumpAndSettle();
}

String fieldText(WidgetTester tester, Key key) {
  final field = find.descendant(
      of: find.byKey(key), matching: find.byType(TextField));
  return tester.widget<TextField>(field).controller?.text ?? '';
}

void main() {
  testWidgets('mode switch hides and shows the right fields',
      (tester) async {
    await pumpLaunch(tester, [core.Game(id: 'g1', title: 'Alpha')]);
    await openLaunch(tester, 'Alpha');
    expect(find.text('Proton version'), findsOneWidget);
    expect(find.text('Prefix'), findsOneWidget);
    expect(find.text('Steam app id'), findsNothing);

    await tester.tap(find.byKey(const Key('mode-native')));
    await tester.pumpAndSettle();
    expect(find.text('Executable'), findsOneWidget);
    expect(find.text('Proton version'), findsNothing);
    expect(find.text('Wine build'), findsNothing);
    expect(find.text('Prefix'), findsNothing);
    expect(find.text('Game language'), findsNothing);

    await tester.tap(find.byKey(const Key('mode-steam')));
    await tester.pumpAndSettle();
    expect(find.text('Steam app id'), findsOneWidget);
    expect(find.text('Executable'), findsNothing);
    expect(find.text('Arguments'), findsNothing);

    await tester.tap(find.byKey(const Key('mode-wine')));
    await tester.pumpAndSettle();
    expect(find.text('Wine build'), findsOneWidget);
    expect(find.text('Prefix'), findsOneWidget);
    expect(find.text('Steam app id'), findsNothing);
  });

  testWidgets('text field saves on blur and Esc reverts', (tester) async {
    final repo = await pumpLaunch(tester, [core.Game(id: 'g1', title: 'Alpha')]);
    await openLaunch(tester, 'Alpha');
    await openAdvanced(tester);
    await tester.enterText(
        find.byKey(const Key('launch-umu')), 'umu-12345');
    await blur(tester);
    expect(repo.games.first.launch.umuGameId, 'umu-12345');

    await tester.enterText(
        find.byKey(const Key('launch-umu')), 'umu-changed');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(repo.games.first.launch.umuGameId, 'umu-12345');
    expect(fieldText(tester, const Key('launch-umu')), 'umu-12345');
  });

  testWidgets('clearing the executable saves null', (tester) async {
    final repo = await pumpLaunch(tester, [
      core.Game(
          id: 'g1',
          title: 'Alpha',
          launch: core.LaunchOverrides(executable: '/games/a.exe')),
    ]);
    await openLaunch(tester, 'Alpha');
    expect(fieldText(tester, const Key('launch-executable')), '/games/a.exe');
    await tester.enterText(find.byKey(const Key('launch-executable')), '');
    await blur(tester);
    expect(repo.games.first.launch.executable, isNull);
  });

  testWidgets('an unknown runner value shows Custom with the value',
      (tester) async {
    await pumpLaunch(tester, [
      core.Game(
          id: 'g1',
          title: 'Alpha',
          launch: core.LaunchOverrides(
              mode: core.LaunchMode.wine, runner: '/custom/wine')),
    ]);
    await openLaunch(tester, 'Alpha');
    expect(
      tester
          .widget<SettingsDropdown<String>>(
              find.byKey(const Key('launch-runner')))
          .value,
      'custom',
    );
    expect(find.text('Custom…'), findsOneWidget);
    expect(
        fieldText(tester, const Key('launch-runner-custom')), '/custom/wine');
  });

  testWidgets('picking a detected Proton runner saves its path',
      (tester) async {
    final repo = await pumpLaunch(
      tester,
      [core.Game(id: 'g1', title: 'Alpha')],
      protons: const [
        detect.ProtonRunner(name: 'GE-9', path: '/steam/ge-9'),
      ],
    );
    await openLaunch(tester, 'Alpha');
    await tester.ensureVisible(find.byKey(const Key('launch-runner')));
    await tester.tap(find.byKey(const Key('launch-runner')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('GE-9').last);
    await tester.pumpAndSettle();
    expect(repo.games.first.launch.runner, '/steam/ge-9');
  });

  testWidgets('a portal path is rejected', (tester) async {
    final repo = await pumpLaunch(
      tester,
      [
        core.Game(
            id: 'g1',
            title: 'Alpha',
            launch: core.LaunchOverrides(executable: '/real/game.exe')),
      ],
      pathPicker: ({String? initialDirectory, PathPickMode mode = PathPickMode.file}) async =>
          '/run/user/1000/real/picked.exe',
    );
    await openLaunch(tester, 'Alpha');
    await tester.ensureVisible(find.byKey(const Key('launch-executable-choose')));
    await tester.tap(find.byKey(const Key('launch-executable-choose')));
    await tester.pump();
    await tester.pump();
    expect(repo.games.first.launch.executable, '/real/game.exe');
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('a non-digit Steam id shows the error and does not save',
      (tester) async {
    final repo = await pumpLaunch(tester, [
      core.Game(
          id: 'g1',
          title: 'Alpha',
          launch: core.LaunchOverrides(mode: core.LaunchMode.steam)),
    ]);
    await openLaunch(tester, 'Alpha');
    await tester.enterText(
        find.byKey(const Key('launch-steam-app-id')), '12ab');
    await blur(tester);
    expect(find.text('Steam App ID must be digits.'), findsOneWidget);
    expect(repo.games.first.launch.steamAppId, isNull);

    await tester.enterText(
        find.byKey(const Key('launch-steam-app-id')), '123');
    await blur(tester);
    expect(repo.games.first.launch.steamAppId, 123);
  });

  testWidgets('a bad args quote shows the error and does not save',
      (tester) async {
    final repo = await pumpLaunch(tester, [core.Game(id: 'g1', title: 'Alpha')]);
    await openLaunch(tester, 'Alpha');
    await openAdvanced(tester);
    await tester.enterText(
        find.byKey(const Key('launch-arguments')), '--foo "unclosed');
    await blur(tester);
    expect(repo.games.first.launch.arguments, isNull);
    expect(find.textContaining('Unclosed'), findsWidgets);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
  });

  testWidgets('a bad env line shows the error and does not save',
      (tester) async {
    final repo = await pumpLaunch(tester, [core.Game(id: 'g1', title: 'Alpha')]);
    await openLaunch(tester, 'Alpha');
    await openAdvanced(tester);
    await tester.enterText(
        find.byKey(const Key('launch-environment')), 'NOEQUALS');
    await blur(tester);
    expect(repo.games.first.launch.environment, isNull);
    expect(find.text('Line 1 must be KEY=value'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
  });

  testWidgets('the args preview count is right', (tester) async {
    await pumpLaunch(tester, [core.Game(id: 'g1', title: 'Alpha')]);
    await openLaunch(tester, 'Alpha');
    await openAdvanced(tester);
    expect(find.text('Splits into 0 arguments'), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('launch-arguments')), '--foo "a b"');
    await tester.pump();
    expect(find.text('Splits into 2 arguments'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
  });

  testWidgets('mode segment saves the picked mode', (tester) async {
    final repo = await pumpLaunch(tester, [core.Game(id: 'g1', title: 'Alpha')]);
    await openLaunch(tester, 'Alpha');
    await tester.tap(find.byKey(const Key('mode-native')));
    await tester.pumpAndSettle();
    expect(repo.games.first.launch.mode, core.LaunchMode.native);
    expect(find.text('Executable'), findsOneWidget);
    expect(find.text('Proton version'), findsNothing);
    expect(find.text('Wine build'), findsNothing);
  });

  testWidgets('a stored mode missing from the list stays selected',
      (tester) async {
    await pumpLaunch(
      tester,
      [
        core.Game(
            id: 'g1',
            title: 'Alpha',
            launch: core.LaunchOverrides(mode: core.LaunchMode.native)),
      ],
      launchModes: const [core.LaunchMode.proton, core.LaunchMode.wine],
    );
    await openLaunch(tester, 'Alpha');
    final native = tester.widget<ToolbarSegment>(
        find.byKey(const Key('mode-native')));
    expect(native.selected, isTrue);
    expect(
        tester
            .widget<ToolbarSegment>(find.byKey(const Key('mode-proton')))
            .selected,
        isFalse);
  });

  testWidgets('inherited values carry a Default note', (tester) async {
    await pumpLaunch(tester, [core.Game(id: 'g1', title: 'Alpha')]);
    await openLaunch(tester, 'Alpha');
    expect(find.text('Default'), findsWidgets);
    expect(find.text('Mode'), findsOneWidget);
  });

  testWidgets('Advanced is collapsed by default and expands', (tester) async {
    await pumpLaunch(tester, [core.Game(id: 'g1', title: 'Alpha')]);
    await openLaunch(tester, 'Alpha');
    expect(find.text('Arguments'), findsNothing);
    expect(find.text('Show'), findsOneWidget);
    await openAdvanced(tester);
    expect(find.text('Arguments'), findsOneWidget);
    expect(find.text('Environment'), findsOneWidget);
    expect(find.text('Hide'), findsOneWidget);
  });

  testWidgets('Rescan reruns the runner scan', (tester) async {
    var scans = 0;
    await pumpLaunch(tester, [core.Game(id: 'g1', title: 'Alpha')],
        onRunnerScan: () => scans++);
    await openLaunch(tester, 'Alpha');
    final before = scans;
    await tester.ensureVisible(find.byKey(const Key('launch-rescan')));
    await tester.tap(find.byKey(const Key('launch-rescan')));
    await tester.pumpAndSettle();
    expect(scans, greaterThan(before));
  });

  testWidgets('Choose is a glass button', (tester) async {
    await pumpLaunch(tester, [core.Game(id: 'g1', title: 'Alpha')]);
    await openLaunch(tester, 'Alpha');
    expect(
        tester.widget(find.byKey(const Key('launch-executable-choose'))),
        isA<BrandGlassButton>());
  });

  testWidgets('single-line boxes are 40 px and share a centre line with Choose',
      (tester) async {
    await pumpLaunch(tester, [
      core.Game(
          id: 'g1',
          title: 'Alpha',
          launch: core.LaunchOverrides(
              mode: core.LaunchMode.proton,
              executable: '/games/a.exe',
              prefix: '/custom/prefix',
              umuGameId: 'umu-1',
              arguments: '--x')),
    ]);
    await openLaunch(tester, 'Alpha');
    await openAdvanced(tester);
    Finder boxOf(String key) => find.descendant(
        of: find.byKey(Key(key)), matching: find.byType(InputDecorator));
    Finder borderOf(String key) => find.descendant(
        of: find.byKey(Key(key)), matching: find.byType(SettingsTextBox));
    for (final key in [
      'launch-executable',
      'launch-prefix-custom',
      'launch-umu',
      'launch-arguments',
    ]) {
      expect(tester.getSize(boxOf(key)).height, closeTo(40, 1), reason: key);
      expect(tester.getSize(borderOf(key)).height, closeTo(40, 1),
          reason: '$key border');
      expect(tester.getCenter(borderOf(key)).dy,
          closeTo(tester.getCenter(boxOf(key)).dy, 1),
          reason: '$key decorator centre');
    }
    for (final pair in [
      ('launch-executable', 'launch-executable-choose'),
      ('launch-prefix-custom', 'launch-prefix-choose'),
    ]) {
      final box = tester.getCenter(boxOf(pair.$1));
      final choose = tester.getCenter(find.byKey(Key(pair.$2)));
      expect((box.dy - choose.dy).abs(), lessThanOrEqualTo(1), reason: pair.$1);
    }
  });

  testWidgets('environment is a top-aligned box of at least 72 px',
      (tester) async {
    await pumpLaunch(tester, [core.Game(id: 'g1', title: 'Alpha')]);
    await openLaunch(tester, 'Alpha');
    await openAdvanced(tester);
    final env = find.descendant(
        of: find.byKey(const Key('launch-environment')),
        matching: find.byType(TextField));
    expect(tester.getSize(find.descendant(
        of: find.byKey(const Key('launch-environment')),
        matching: find.byType(SettingsTextBox))).height,
        greaterThanOrEqualTo(72));
    expect(tester.widget<TextField>(env).textAlignVertical,
        TextAlignVertical.top);
    expect(tester.getSize(find.descendant(
        of: find.byKey(const Key('launch-environment')),
        matching: find.byType(SettingsTextBox))).height,
        greaterThanOrEqualTo(72));
    expect(find.text('KEY=value, one per line'), findsOneWidget);
    expect(find.text('None'), findsOneWidget);
  });

  testWidgets('the locale dropdown uses the settings language names',
      (tester) async {
    await pumpLaunch(tester, [core.Game(id: 'g1', title: 'Alpha')]);
    await openLaunch(tester, 'Alpha');
    expect(find.text('Game language'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('launch-locale')));
    await tester.tap(find.byKey(const Key('launch-locale')));
    await tester.pumpAndSettle();
    for (final name in ['System', 'Japanese', 'Chinese', 'Korean', 'English']) {
      expect(find.text(name), findsWidgets);
    }
    expect(find.text('ja_JP.UTF-8'), findsNothing);
  });

  testWidgets('an unfocused path overlay sits inside the 1 px border',
      (tester) async {
    await pumpLaunch(tester, [
      core.Game(
          id: 'g1',
          title: 'Alpha',
          launch: core.LaunchOverrides(executable: '/games/alpha/run.exe')),
    ]);
    await openLaunch(tester, 'Alpha');
    final box = tester.getRect(find.descendant(
        of: find.byKey(const Key('launch-executable')),
        matching: find.byType(SettingsTextBox)));
    final overlay = find.descendant(
        of: find.byKey(const Key('launch-executable')),
        matching: find.byType(MiddleEllipsisValue));
    expect(overlay, findsOneWidget);
    final clip = tester.getRect(find.descendant(
        of: overlay, matching: find.byType(ClipRRect)));
    expect(clip.top, closeTo(box.top + 1, 0.5));
    expect(clip.bottom, closeTo(box.bottom - 1, 0.5));
    expect(clip.left, closeTo(box.left + 1, 0.5));
    expect(clip.right, closeTo(box.right - 1, 0.5));
  });

  testWidgets('single-line text is centred in each box, unfocused and focused',
      (tester) async {
    await pumpLaunch(tester, [
      core.Game(
          id: 'g1',
          title: 'Alpha',
          launch: core.LaunchOverrides(
              mode: core.LaunchMode.proton,
              executable: '/games/a.exe',
              umuGameId: 'umu-1',
              arguments: '--x')),
    ]);
    await openLaunch(tester, 'Alpha');
    await openAdvanced(tester);
    for (final key in ['launch-executable', 'launch-umu', 'launch-arguments']) {
      final box = find.descendant(
          of: find.byKey(Key(key)), matching: find.byType(SettingsTextBox));
      final editable = find.descendant(
          of: find.byKey(Key(key)), matching: find.byType(EditableText));
      expect(tester.getCenter(editable).dy,
          closeTo(tester.getCenter(box).dy, 2), reason: '$key unfocused');
      await tester.ensureVisible(editable);
      await tester.pump();
      expect(tester.getCenter(editable).dy,
          closeTo(tester.getCenter(box).dy, 2), reason: '$key scrolled');
      await tester.tap(editable);
      await tester.pump();
      expect(tester.getCenter(editable).dy,
          closeTo(tester.getCenter(box).dy, 2), reason: '$key focused');
      await tester.enterText(find.byKey(Key(key)), 'typed value');
      await tester.pump();
      expect(tester.getCenter(editable).dy,
          closeTo(tester.getCenter(box).dy, 2), reason: '$key typing');
      await blur(tester);
      await tester.pumpAndSettle();
    }
    await tester.pump(const Duration(seconds: 6));
  });
}
