// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumige/src/core/covers.dart' as core;
import 'package:tsumige/src/core/launch/detect.dart' as detect;
import 'package:tsumige/src/core/model.dart' as core;
import 'package:tsumige/src/core/paths.dart' as core;
import 'package:tsumige/src/core/vndb.dart' as core;
import 'package:tsumige/src/features/library/data/library_repository.dart';
import 'package:tsumige/src/features/library/domain/runner_detection.dart';
import 'package:tsumige/src/features/settings/presentation/settings_dialog.dart';
import 'package:tsumige/src/l10n/generated/app_localizations.dart';
import 'package:tsumige/src/utils/prefs/app_prefs.dart';
import 'package:tsumige/src/utils/prefs/prefs_mixin.dart';

class _FakeRepository implements LibraryRepository {
  @override
  Future<core.LoadedLibrary> load() async => core.LoadedLibrary(
    library: core.Library(games: [core.Game(id: 'g1', title: 'Alpha')]),
  );

  @override
  Future<void> save(core.LoadedLibrary loaded) async {}

  @override
  Future<core.VndbRefreshReport> refreshVndbData(
    core.LoadedLibrary loaded,
  ) async => const core.VndbRefreshReport();

  @override
  Future<core.ThumbReport> ensureThumbnails(core.Library library) async =>
      core.ThumbReport();
}

Future<ProviderContainer> _pumpLibrary(
  WidgetTester tester, {
  List<Uri>? openedUris,
}) async {
  tester.view.physicalSize = const Size(1400, 980);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  SettingsDialog.lastSection = SettingsSection.appearance;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        dataDirProvider.overrideWithValue(core.DataDir('/tmp/tsumige_test')),
        libraryRepositoryProvider.overrideWithValue(_FakeRepository()),
        protonRunnersProvider.overrideWith(
          (ref) => Future.value(const <detect.ProtonRunner>[]),
        ),
        folderOpenerProvider.overrideWithValue((uri) async {
          openedUris?.add(uri);
          return true;
        }),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                key: const Key('open-settings'),
                onPressed: () => showSettingsDialog(context),
                child: const Text('Open settings'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.tap(find.byKey(const Key('open-settings')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('settings-nav-library')));
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(SettingsDialog)));
}

void main() {
  testWidgets('the SteamGridDB group renders with an obscured field', (
    tester,
  ) async {
    await _pumpLibrary(tester);
    expect(find.text('SteamGridDB'), findsOneWidget);
    expect(
      find.text(
        'Optional. Adds covers from steamgriddb.com to Change art. '
        'Uses your own API key, stored on this computer.',
      ),
      findsOneWidget,
    );
    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('settings-steamgriddb-key')),
        matching: find.byType(TextField),
      ),
    );
    expect(field.obscureText, isTrue);
    expect(find.text('Get a key'), findsOneWidget);
  });

  testWidgets('entering a key persists it', (tester) async {
    final container = await _pumpLibrary(tester);
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('settings-steamgriddb-key')),
        matching: find.byType(TextField),
      ),
      '  fake-test-key  ',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(container.read(steamGridDbKeyProvider), 'fake-test-key');
  });

  testWidgets('clearing the key turns the source off', (tester) async {
    final container = await _pumpLibrary(tester);
    final field = find.descendant(
      of: find.byKey(const Key('settings-steamgriddb-key')),
      matching: find.byType(TextField),
    );
    await tester.enterText(field, 'fake-test-key');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(container.read(steamGridDbKeyProvider), 'fake-test-key');
    await tester.enterText(field, '');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(container.read(steamGridDbKeyProvider), isEmpty);
  });
}
