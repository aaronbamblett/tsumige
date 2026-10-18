// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumige/src/features/settings/presentation/sections/about_section.dart';
import 'package:tsumige/src/utils/prefs/prefs_mixin.dart';
import 'package:tsumige/src/utils/theme/brand.dart';

void main() {
  testWidgets('GitHub button opens the repository through the opener', (
    tester,
  ) async {
    final opened = <Uri>[];
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
          githubUrlOpenerProvider.overrideWithValue((uri) async {
            opened.add(uri);
            return true;
          }),
        ],
        child: const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: AboutSection())),
        ),
      ),
    );

    final button = find.widgetWithText(BrandGlassButton, 'GitHub');
    expect(button, findsOneWidget);
    await tester.tap(button);
    await tester.pump();
    expect(opened, [Uri.parse('https://github.com/aaronbamblett/tsumige')]);
  });
}
