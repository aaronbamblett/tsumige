// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:vnl/src/core/covers.dart' as core;
import 'package:vnl/src/core/launch/detect.dart' as detect;
import 'package:vnl/src/core/model.dart' as core;
import 'package:vnl/src/core/paths.dart' as core;
import 'package:vnl/src/core/store.dart' as core;
import 'package:vnl/src/core/vndb.dart' as core;
import 'package:vnl/src/features/library/data/library_repository.dart';
import 'package:vnl/src/features/library/domain/game_editor.dart';
import 'package:vnl/src/features/library/domain/runner_detection.dart';
import 'package:vnl/src/features/settings/presentation/appearance/widgets/app_theme_selector/app_theme_selector.dart';
import 'package:vnl/src/features/settings/presentation/appearance/widgets/is_true_black/is_true_black_tile.dart';
import 'package:vnl/src/features/settings/presentation/settings_screen.dart';
import 'package:vnl/src/features/settings/widgets/app_theme_mode_tile/app_theme_mode_tile.dart';
import 'package:vnl/src/l10n/generated/app_localizations.dart';
import 'package:vnl/src/utils/prefs/app_prefs.dart';
import 'package:vnl/src/utils/prefs/prefs_mixin.dart';

class SettingsFakeRepository implements LibraryRepository {
  SettingsFakeRepository({
    this.report = const core.RatingReport(),
    this.saveError,
    this.gate,
    this.skipped = const [],
  });

  core.RatingReport report;
  Object? saveError;
  Completer<core.RatingReport>? gate;
  List<core.SkippedEntry> skipped;
  int loadCount = 0;
  int refreshCount = 0;
  int saveCount = 0;

  @override
  Future<core.LoadedLibrary> load() async {
    loadCount++;
    return core.LoadedLibrary(
      library: core.Library(games: [
        core.Game(id: 'g1', title: 'Alpha', vndbId: 'v1'),
      ]),
      skipped: skipped,
    );
  }

  @override
  Future<void> save(core.LoadedLibrary loaded) async {
    saveCount++;
    final error = saveError;
    if (error != null) throw error;
  }

  @override
  Future<core.RatingReport> refreshRatings(core.LoadedLibrary loaded) async {
    refreshCount++;
    final pending = gate;
    if (pending != null) return pending.future;
    return report;
  }

  @override
  Future<core.ThumbReport> ensureThumbnails(core.Library library) async =>
      core.ThumbReport();
}

Future<ProviderContainer> pumpSettings(
  WidgetTester tester,
  SettingsFakeRepository repo, {
  core.DataDir? dir,
  List<detect.ProtonRunner> protonRunners = const [],
  Future<String?> Function({String? initialDirectory, PathPickMode mode})?
      pathPicker,
  List<Uri>? openedUris,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      dataDirProvider
          .overrideWithValue(dir ?? core.DataDir('/tmp/vnl_test')),
      libraryRepositoryProvider.overrideWithValue(repo),
      protonRunnersProvider.overrideWith((ref) => Future.value(protonRunners)),
      if (pathPicker != null)
        pathPickerProvider.overrideWithValue(pathPicker),
      folderOpenerProvider.overrideWithValue((uri) async {
        openedUris?.add(uri);
        return true;
      }),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const SettingsScreen(),
    ),
  ));
  await tester.pump();
  await tester.pump();
  return ProviderScope.containerOf(
      tester.element(find.byType(SettingsScreen)));
}

Finder refreshTile() =>
    find.widgetWithText(ListTile, 'Refresh VNDB ratings');

void setTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void main() {
  testWidgets('refresh tile disabled while running', (tester) async {
    final gate = Completer<core.RatingReport>();
    final repo = SettingsFakeRepository(
      gate: gate,
      report: const core.RatingReport(updated: 1),
    );
    await pumpSettings(tester, repo);
    await tester.tap(refreshTile());
    await tester.pump();
    expect(tester.widget<ListTile>(refreshTile()).enabled, isFalse);
    expect(repo.refreshCount, 1);
    await tester.tap(refreshTile());
    await tester.pump();
    expect(repo.refreshCount, 1);
    gate.complete(const core.RatingReport(updated: 1));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(tester.widget<ListTile>(refreshTile()).enabled, isTrue);
    expect(repo.refreshCount, 1);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('changed on disk reloads', (tester) async {
    final repo = SettingsFakeRepository(
      report: const core.RatingReport(updated: 2),
      saveError: core.ChangedOnDisk('x'),
    );
    await pumpSettings(tester, repo);
    expect(repo.loadCount, 1);
    await tester.tap(refreshTile());
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(repo.saveCount, 1);
    expect(repo.loadCount, 2);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('skipped entries never fetch ratings', (tester) async {
    final repo = SettingsFakeRepository(
      report: const core.RatingReport(updated: 2),
      skipped: const [core.SkippedEntry(index: 0, reason: 'bad id')],
    );
    await pumpSettings(tester, repo);
    expect(repo.loadCount, 1);
    await tester.tap(refreshTile());
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(repo.refreshCount, 0);
    expect(repo.saveCount, 0);
    expect(repo.loadCount, 1);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('generic save failure reloads', (tester) async {
    final repo = SettingsFakeRepository(
      report: const core.RatingReport(updated: 2),
      saveError: const FileSystemException('disk gone'),
    );
    await pumpSettings(tester, repo);
    expect(repo.loadCount, 1);
    await tester.tap(refreshTile());
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(repo.saveCount, 1);
    expect(repo.loadCount, 2);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('zero updates skips save', (tester) async {
    final repo = SettingsFakeRepository(
      report: const core.RatingReport(updated: 0),
    );
    await pumpSettings(tester, repo);
    await tester.tap(refreshTile());
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(repo.saveCount, 0);
    expect(repo.loadCount, 2);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('slider writes cover width', (tester) async {
    final repo = SettingsFakeRepository();
    final container = await pumpSettings(tester, repo);
    expect(container.read(coverWidthProvider), 192);
    await tester.drag(find.byType(Slider), const Offset(200, 0));
    await tester.pump();
    expect(container.read(coverWidthProvider), greaterThan(192));
  });

  testWidgets('data folder shown', (tester) async {
    // The theme header row pushes this tile below the fold on the default
    // surface; a tall surface keeps the whole settings list built.
    setTallSurface(tester);
    await pumpSettings(tester, SettingsFakeRepository(),
        dir: core.DataDir('/tmp/x'));
    expect(find.text('/tmp/x'), findsOneWidget);
  });

  testWidgets('appearance theme controls render', (tester) async {
    await pumpSettings(tester, SettingsFakeRepository());
    expect(find.byType(AppThemeModeTile), findsOneWidget);
    expect(find.byType(ThemeSelector), findsOneWidget);
    expect(find.byType(IsTrueBlackTile), findsOneWidget);
    expect(find.byType(CustomColorTile), findsNothing);
  });

  testWidgets('default mode dropdown writes the pref', (tester) async {
    setTallSurface(tester);
    final container =
        await pumpSettings(tester, SettingsFakeRepository());
    expect(container.read(launchModeProvider), core.LaunchMode.proton);
    await tester.tap(find.byKey(const Key('settings-default-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wine').last);
    await tester.pumpAndSettle();
    expect(container.read(launchModeProvider), core.LaunchMode.wine);
  });

  testWidgets('default prefix text writes the pref, portal is rejected',
      (tester) async {
    setTallSurface(tester);
    final container =
        await pumpSettings(tester, SettingsFakeRepository());
    final field = find.byKey(const Key('settings-default-prefix'));
    await tester.enterText(field, '/games/prefix');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    expect(container.read(launchPrefixProvider), '/games/prefix');

    await tester.enterText(field, '/run/user/1000/prefix');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    expect(container.read(launchPrefixProvider), '/games/prefix');
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('default prefix picker writes the pref', (tester) async {
    setTallSurface(tester);
    final container = await pumpSettings(tester, SettingsFakeRepository(),
        pathPicker: ({String? initialDirectory, PathPickMode mode = PathPickMode.file}) async => '/picked/prefix');
    final button = find.byKey(const Key('settings-default-prefix-choose'));
    await tester.tap(button);
    await tester.pump();
    await tester.pump();
    expect(container.read(launchPrefixProvider), '/picked/prefix');
  });

  testWidgets('default Proton runner dropdown writes the pref',
      (tester) async {
    setTallSurface(tester);
    final container = await pumpSettings(tester, SettingsFakeRepository(),
        protonRunners: const [
          detect.ProtonRunner(name: 'GE-9', path: '/steam/ge-9'),
        ]);
    expect(container.read(launchRunnerProvider), isNull);
    await tester.tap(find.byKey(const Key('settings-default-runner')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('GE-9').last);
    await tester.pumpAndSettle();
    expect(container.read(launchRunnerProvider), '/steam/ge-9');
  });

  testWidgets('default Proton runner custom shows a field', (tester) async {
    setTallSurface(tester);
    await pumpSettings(tester, SettingsFakeRepository());
    await tester.tap(find.byKey(const Key('settings-default-runner')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom…').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-default-runner-custom')),
        findsOneWidget);
  });

  testWidgets('default locale dropdown writes the pref', (tester) async {
    setTallSurface(tester);
    final container =
        await pumpSettings(tester, SettingsFakeRepository());
    await tester.tap(find.byKey(const Key('settings-default-locale')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ko_KR.UTF-8').last);
    await tester.pumpAndSettle();
    expect(container.read(launchLocaleProvider), 'ko_KR.UTF-8');
  });

  testWidgets('default UMU id writes the pref', (tester) async {
    setTallSurface(tester);
    final container =
        await pumpSettings(tester, SettingsFakeRepository());
    final field = find.byKey(const Key('settings-default-umu'));
    await tester.enterText(field, 'umu-test');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    expect(container.read(launchUmuGameIdProvider), 'umu-test');
  });

  testWidgets('open-folder buttons call the injected launcher',
      (tester) async {
    setTallSurface(tester);
    final temp = Directory.systemTemp.createTempSync('vnl_settings_test_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final opened = <Uri>[];
    await pumpSettings(tester, SettingsFakeRepository(),
        dir: core.DataDir(temp.path), openedUris: opened);
    final dataButton = find.byKey(const Key('settings-open-data'));
    await tester.tap(dataButton);
    await tester.pump();
    await tester.pump();
    expect(opened, [Uri.file(temp.path)]);

    final logsButton = find.byKey(const Key('settings-open-logs'));
    await tester.tap(logsButton);
    await tester.pump();
    await tester.pump();
    expect(opened, [Uri.file(temp.path), Uri.file(p.join(temp.path, 'logs'))]);
    expect(Directory(p.join(temp.path, 'logs')).existsSync(), isTrue);
  });
}
