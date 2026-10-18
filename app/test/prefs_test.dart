// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumige/src/constants/pref_keys.dart' as keys;
import 'package:tsumige/src/utils/prefs/app_prefs.dart';
import 'package:tsumige/src/utils/prefs/prefs_mixin.dart';

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
    expect(container.read(coverWidthProvider), 400);
  });

  test('clampCoverWidth bounds', () {
    expect(keys.clampCoverWidth(999), 400);
    expect(keys.clampCoverWidth(50), 100);
    expect(keys.clampCoverWidth(192), 192);
  });

  test('stored cover width above max loads clamped', () async {
    SharedPreferences.setMockInitialValues(
        {keys.PrefKey.coverWidth.key: 999});
    final prefs = await SharedPreferences.getInstance();
    final container = containerFor(prefs);
    addTearDown(container.dispose);

    expect(container.read(coverWidthProvider), 400);
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

  test('detail fields default to all four', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = containerFor(prefs);
    addTearDown(container.dispose);

    expect(container.read(detailFieldsProvider), keys.detailFieldsAll);
  });

  test('detail fields round-trip', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = containerFor(prefs);
    addTearDown(container.dispose);

    container
        .read(detailFieldsProvider.notifier)
        .set({keys.detailFieldDescription, keys.detailFieldNotes});
    expect(
      container.read(detailFieldsProvider),
      {keys.detailFieldDescription, keys.detailFieldNotes},
    );

    final rebuilt = containerFor(prefs);
    addTearDown(rebuilt.dispose);
    expect(
      rebuilt.read(detailFieldsProvider),
      {keys.detailFieldDescription, keys.detailFieldNotes},
    );
  });

  test('detail fields garbage means all four', () async {
    SharedPreferences.setMockInitialValues(
        {keys.PrefKey.detailFields.key: <String>['bogus']});
    final prefs = await SharedPreferences.getInstance();
    final container = containerFor(prefs);
    addTearDown(container.dispose);

    expect(container.read(detailFieldsProvider), keys.detailFieldsAll);
  });

  test('detail fields wrong-type stored value means all four', () async {
    SharedPreferences.setMockInitialValues(
        {keys.PrefKey.detailFields.key: 42});
    final prefs = await SharedPreferences.getInstance();
    final container = containerFor(prefs);
    addTearDown(container.dispose);

    expect(container.read(detailFieldsProvider), keys.detailFieldsAll);
  });

  test('launch defaults read back', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = containerFor(prefs);
    addTearDown(container.dispose);

    expect(container.read(launchPrefixProvider), '~/Games/tsumige/prefix');
    expect(container.read(launchRunnerProvider), isNull);
    expect(container.read(launchLocaleProvider), 'ja_JP.UTF-8');
    expect(container.read(launchUmuGameIdProvider), 'umu-default');
  });
}
