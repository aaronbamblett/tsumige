// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vnl/src/constants/pref_keys.dart' as keys;
import 'package:vnl/src/core/model.dart' as core;
import 'package:vnl/src/utils/prefs/app_prefs.dart';
import 'package:vnl/src/utils/prefs/prefs_mixin.dart';

ProviderContainer containerFor(SharedPreferences prefs) =>
    ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);

void main() {
  test('cover width defaults and clamps', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = containerFor(prefs);
    addTearDown(container.dispose);

    expect(container.read(coverWidthProvider), 192);

    container.read(coverWidthProvider.notifier).set(50);
    expect(container.read(coverWidthProvider), 100);

    container.read(coverWidthProvider.notifier).set(1500);
    expect(container.read(coverWidthProvider), 999);
  });

  test('sort persists', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = containerFor(prefs);
    addTearDown(container.dispose);

    container.read(sortFieldProvider.notifier).set(keys.SortField.title);
    container.read(sortAscendingProvider.notifier).set(false);

    final rebuilt = containerFor(prefs);
    addTearDown(rebuilt.dispose);
    expect(rebuilt.read(sortFieldProvider), keys.SortField.title);
    expect(rebuilt.read(sortAscendingProvider), isFalse);
  });

  test('launch defaults read back', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = containerFor(prefs);
    addTearDown(container.dispose);

    expect(container.read(launchModeProvider), core.LaunchMode.proton);
    expect(container.read(launchPrefixProvider), '~/Games/vnl/prefix');
    expect(container.read(launchRunnerProvider), isNull);
    expect(container.read(launchLocaleProvider), 'ja_JP.UTF-8');
    expect(container.read(launchUmuGameIdProvider), 'umu-default');
  });
}
