// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumige/main.dart';
import 'package:tsumige/src/features/library/data/library_repository.dart';
import 'package:tsumige/src/utils/prefs/prefs_mixin.dart';
import 'package:tsumige/src/core/covers.dart' as core;
import 'package:tsumige/src/core/model.dart' as core;
import 'package:tsumige/src/core/paths.dart' as core;
import 'package:tsumige/src/core/store.dart' as core;
import 'package:tsumige/src/core/vndb.dart' as core;

class ThrowingLibrary extends Library {
  ThrowingLibrary(this.error);

  final core.StoreException error;

  @override
  Future<core.LoadedLibrary> build() async => throw error;
}

class ThrowingRepository implements LibraryRepository {
  ThrowingRepository(this.error);

  final core.StoreException error;
  int loads = 0;

  @override
  Future<core.LoadedLibrary> load() async {
    loads++;
    throw error;
  }

  @override
  Future<void> save(core.LoadedLibrary loaded) async {}

  @override
  Future<core.VndbRefreshReport> refreshVndbData(core.LoadedLibrary loaded) async =>
      const core.VndbRefreshReport();

  @override
  Future<core.ThumbReport> ensureThumbnails(core.Library library) async =>
      core.ThumbReport();
}

class CountingRepository implements LibraryRepository {
  int loads = 0;

  @override
  Future<core.LoadedLibrary> load() async {
    loads++;
    return core.LoadedLibrary(library: core.Library());
  }

  @override
  Future<void> save(core.LoadedLibrary loaded) async {}

  @override
  Future<core.VndbRefreshReport> refreshVndbData(core.LoadedLibrary loaded) async =>
      const core.VndbRefreshReport();

  @override
  Future<core.ThumbReport> ensureThumbnails(core.Library library) async =>
      core.ThumbReport();
}

Future<SharedPreferences> mockPrefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

void main() {
  testWidgets('corrupt library shows error screen', (tester) async {
    final temp =
        Directory.systemTemp.createTempSync('tsumige_startup_error_test_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final dir = core.DataDir(temp.path);
    final error =
        core.InvalidJson(dir.libraryJson.path, 'unexpected end of input');

    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider
            .overrideWithValue(await mockPrefs()),
        dataDirProvider.overrideWithValue(dir),
        libraryProvider.overrideWith(() => ThrowingLibrary(error)),
      ],
      child: const TsumigeApp(),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining(dir.libraryJson.path), findsWidgets);
    expect(find.textContaining('backups'), findsWidgets);
  });

  testWidgets('failed library load is not retried', (tester) async {
    final temp = Directory.systemTemp.createTempSync('tsumige_startup_retry_test_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final dir = core.DataDir(temp.path);
    final repository = ThrowingRepository(
      core.InvalidJson(dir.libraryJson.path, 'unexpected end of input'),
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider
            .overrideWithValue(await mockPrefs()),
        dataDirProvider.overrideWithValue(dir),
        libraryRepositoryProvider.overrideWithValue(repository),
      ],
      child: const TsumigeApp(),
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));

    expect(repository.loads, 1);
    expect(find.textContaining(dir.libraryJson.path), findsWidgets);
  });

  testWidgets('library loads once', (tester) async {
    final temp = Directory.systemTemp.createTempSync('tsumige_startup_load_test_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final repository = CountingRepository();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider
            .overrideWithValue(await mockPrefs()),
        dataDirProvider.overrideWithValue(core.DataDir(temp.path)),
        libraryRepositoryProvider.overrideWithValue(repository),
      ],
      child: const TsumigeApp(),
    ));
    await tester.pumpAndSettle();

    expect(repository.loads, 1);
    expect(find.text('Search visual novels…'), findsOneWidget);
  });
}
