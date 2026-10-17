// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vnl/main.dart';
import 'package:vnl/src/constants/app_theme.dart';
import 'package:vnl/src/core/model.dart' as core;
import 'package:vnl/src/core/paths.dart' as core;
import 'package:vnl/src/features/library/data/library_repository.dart';
import 'package:vnl/src/features/settings/presentation/appearance/widgets/app_theme_selector/app_theme_providers.dart';
import 'package:vnl/src/features/settings/presentation/appearance/widgets/is_true_black/is_true_black_tile.dart';
import 'package:vnl/src/features/settings/widgets/app_theme_mode_tile/app_theme_mode_tile.dart';
import 'package:vnl/src/utils/prefs/prefs_mixin.dart';

class DataLibrary extends Library {
  DataLibrary(this.loaded);

  final core.LoadedLibrary loaded;

  @override
  Future<core.LoadedLibrary> build() async => loaded;
}

Future<ProviderContainer> pumpApp(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final temp = Directory.systemTemp.createTempSync('vnl_theme_test_');
  addTearDown(() => temp.deleteSync(recursive: true));
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      dataDirProvider.overrideWithValue(core.DataDir(temp.path)),
      libraryProvider.overrideWith(
        () => DataLibrary(core.LoadedLibrary(library: core.Library())),
      ),
    ],
    child: const VnlApp(),
  ));
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(VnlApp)));
}

MaterialApp appOf(WidgetTester tester) =>
    tester.widget<MaterialApp>(find.byType(MaterialApp));

void main() {
  testWidgets('empty prefs default to Royal dark', (tester) async {
    await pumpApp(tester);
    expect(
      appOf(tester).darkTheme!.scaffoldBackgroundColor,
      const Color(0xFF0D0B16),
    );
  });

  testWidgets('changing theme updates the background', (tester) async {
    final container = await pumpApp(tester);
    container.read(appThemeKeyProvider.notifier).update(AppTheme.dracula);
    await tester.pump();
    expect(
      appOf(tester).darkTheme!.scaffoldBackgroundColor,
      const Color(0xFF282A36),
    );
    final prefs = container.read(sharedPreferencesProvider);
    expect(prefs.getInt('appearance.appTheme'), AppTheme.dracula.index);
  });

  testWidgets('true black makes the dark background black', (tester) async {
    final container = await pumpApp(tester);
    container.read(isTrueBlackProvider.notifier).update(true);
    await tester.pump();
    expect(
      appOf(tester).darkTheme!.scaffoldBackgroundColor,
      Colors.black,
    );
  });

  testWidgets('light theme uses the light tokens', (tester) async {
    final container = await pumpApp(tester);
    expect(appOf(tester).themeMode, ThemeMode.system);
    expect(
      appOf(tester).theme!.scaffoldBackgroundColor,
      const Color(0xFFF1EBF9),
    );
    container.read(appThemeModeProvider.notifier).update(ThemeMode.light);
    await tester.pump();
    expect(appOf(tester).themeMode, ThemeMode.light);
  });
}
