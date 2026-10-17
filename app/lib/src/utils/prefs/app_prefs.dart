// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../constants/pref_keys.dart' as keys;
import '../../core/model.dart' as core;
import 'prefs_mixin.dart';

part 'app_prefs.g.dart';

/// Cover grid tile width in logical pixels, clamped to 100..400.
@riverpod
class CoverWidth extends _$CoverWidth with PrefsMixin<int> {
  @override
  int build() => keys.clampCoverWidth(initInt(keys.PrefKey.coverWidth));

  void set(int value) => state = keys.clampCoverWidth(value);
}

/// Library sort order. Stored as the enum index; out-of-range reads fall back
/// to [keys.SortField.added].
@riverpod
class SortField extends _$SortField with PrefsMixin<keys.SortField> {
  @override
  keys.SortField build() => initSortField();

  void set(keys.SortField value) => state = value;
}

/// False sorts descending.
@riverpod
class SortAscending extends _$SortAscending with PrefsMixin<bool> {
  @override
  bool build() => initBool(keys.PrefKey.sortAscending);

  void set(bool value) => state = value;
}

@riverpod
class FavouritesOnly extends _$FavouritesOnly with PrefsMixin<bool> {
  @override
  bool build() => initBool(keys.PrefKey.favouritesOnly);

  void set(bool value) => state = value;
}

/// Tag filter; null means no filter.
@riverpod
class TagFilter extends _$TagFilter with PrefsMixin<String?> {
  @override
  String? build() => initString(keys.PrefKey.tagFilter);

  void set(String? value) => state = value;
}

/// Default launch mode for games. Stored by enum name; unknown values fall
/// back to proton. Nothing reads it yet; launching is phase 2.
@riverpod
class LaunchMode extends _$LaunchMode with PrefsMixin<core.LaunchMode> {
  @override
  core.LaunchMode build() => initLaunchMode();

  void set(core.LaunchMode value) => state = value;
}

/// Default Wine/Proton prefix for games. Nothing reads it yet.
@riverpod
class LaunchPrefix extends _$LaunchPrefix with PrefsMixin<String> {
  @override
  String build() => initStringWithDefault(keys.PrefKey.launchPrefix);

  void set(String value) => state = value;
}

/// Default runner override; null means umu's default. Nothing reads it yet.
@riverpod
class LaunchRunner extends _$LaunchRunner with PrefsMixin<String?> {
  @override
  String? build() => initString(keys.PrefKey.launchRunner);

  void set(String? value) => state = value;
}

/// Default locale for launched games. Nothing reads it yet.
@riverpod
class LaunchLocale extends _$LaunchLocale with PrefsMixin<String> {
  @override
  String build() => initStringWithDefault(keys.PrefKey.launchLocale);

  void set(String value) => state = value;
}

/// Default UMU game id for launched games. Nothing reads it yet.
@riverpod
class LaunchUmuGameId extends _$LaunchUmuGameId with PrefsMixin<String> {
  @override
  String build() => initStringWithDefault(keys.PrefKey.launchUmuGameId);

  void set(String value) => state = value;
}
