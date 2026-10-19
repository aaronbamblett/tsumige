// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumige/src/constants/app_theme.dart';
import 'package:tsumige/src/features/settings/presentation/appearance/widgets/app_theme_selector/app_theme_providers.dart';
import 'package:tsumige/src/utils/prefs/prefs_mixin.dart';
import 'package:tsumige/src/utils/theme/app_theme_builder.dart';
import 'package:tsumige/src/widgets/desktop/desktop_title_bar.dart';
import 'package:tsumige/src/widgets/tsumige_logo.dart';

class _Theme extends AppThemeKey {
  _Theme(this.value);

  final AppTheme value;

  @override
  AppTheme? build() => value;
}

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('window_manager'),
          (call) async => false,
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), null);
  });

  Future<void> pumpBar(
    WidgetTester tester,
    AppTheme appTheme,
    Brightness brightness,
  ) async {
    SharedPreferences.setMockInitialValues({});
    return tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
          appThemeKeyProvider.overrideWith(() => _Theme(appTheme)),
        ],
        child: MaterialApp(
          theme: buildAppTheme(
            theme: appTheme,
            brightness: brightness,
            customSeed: Colors.blue,
          ),
          home: const Scaffold(body: DesktopTitleBar()),
        ),
      ),
    );
  }

  for (final appTheme in [AppTheme.royal, AppTheme.plum]) {
    for (final brightness in [Brightness.dark, Brightness.light]) {
      testWidgets(
        'title bar shows the Tsumige logo at 28 under ${appTheme.name} ${brightness.name}',
        (tester) async {
          await pumpBar(tester, appTheme, brightness);

          expect(find.byType(TsumigeLogo), findsOneWidget);
          expect(tester.getSize(find.byType(TsumigeLogo)), const Size(28, 28));
        },
      );
    }
  }
}
