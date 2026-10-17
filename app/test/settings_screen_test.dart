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
import 'package:vnl/src/core/covers.dart' as core;
import 'package:vnl/src/core/model.dart' as core;
import 'package:vnl/src/core/paths.dart' as core;
import 'package:vnl/src/core/store.dart' as core;
import 'package:vnl/src/core/vndb.dart' as core;
import 'package:vnl/src/features/library/data/library_repository.dart';
import 'package:vnl/src/features/settings/presentation/settings_screen.dart';
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
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      dataDirProvider
          .overrideWithValue(dir ?? core.DataDir('/tmp/vnl_test')),
      libraryRepositoryProvider.overrideWithValue(repo),
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
    await pumpSettings(tester, SettingsFakeRepository(),
        dir: core.DataDir('/tmp/x'));
    expect(find.text('/tmp/x'), findsOneWidget);
  });
}
