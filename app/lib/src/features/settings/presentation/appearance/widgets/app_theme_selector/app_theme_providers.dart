// Copyright (c) 2026 Contributors to the Suwayomi project
// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../../constants/app_theme.dart';
import '../../../../../../constants/pref_keys.dart';
import '../../../../../../utils/prefs/prefs_mixin.dart';

part 'app_theme_providers.g.dart';

@riverpod
class AppThemeKey extends _$AppThemeKey with PrefsMixin<AppTheme?> {
  @override
  AppTheme? build() => initNullableEnum(PrefKey.appTheme, AppTheme.values);

  void update(AppTheme? value) => state = value;
}

@riverpod
class CustomThemeColor extends _$CustomThemeColor with PrefsMixin<int?> {
  @override
  int? build() => initNullableInt(PrefKey.customThemeColor);

  void update(int? value) => state = value;
}
