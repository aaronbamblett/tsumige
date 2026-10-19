// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../constants/pref_keys.dart' as keys;
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

/// Adult filter; stored as the enum index, out-of-range reads fall back to
/// [keys.AdultFilter.all].
@riverpod
class AdultFilter extends _$AdultFilter with PrefsMixin<keys.AdultFilter> {
  @override
  keys.AdultFilter build() {
    persistOnChange((next) async =>
        prefs.setInt(keys.PrefKey.adultFilter.key, next.index));
    final stored = prefs.getInt(keys.PrefKey.adultFilter.key);
    if (stored == null || stored < 0 || stored >= keys.AdultFilter.values.length) {
      return keys.AdultFilter.all;
    }
    return keys.AdultFilter.values[stored];
  }

  void set(keys.AdultFilter value) => state = value;
}

/// Tag filter; null means no filter.
@riverpod
class TagFilter extends _$TagFilter with PrefsMixin<String?> {
  @override
  String? build() => initString(keys.PrefKey.tagFilter);

  void set(String? value) => state = value;
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

/// SteamGridDB API key, user-supplied. Empty means the source is off.
@riverpod
class SteamGridDbKey extends _$SteamGridDbKey with PrefsMixin<String> {
  @override
  String build() => initStringWithDefault(keys.PrefKey.steamGridDbKey);

  void set(String value) => state = value.trim();
}

/// Info tab sections shown on the details panel. Stored as a string list, a
/// missing key or any unknown entry means every field is shown.
@riverpod
class DetailFields extends _$DetailFields with PrefsMixin<Set<String>> {
  @override
  Set<String> build() {
    persistOnChange((next) async => prefs.setStringList(
        keys.PrefKey.detailFields.key, next.toList()));
    final raw = prefs.get(keys.PrefKey.detailFields.key);
    if (raw is! List ||
        raw.any((e) => e is! String || !keys.detailFieldsAll.contains(e))) {
      return keys.detailFieldsAll;
    }
    return raw.cast<String>().toSet();
  }

  void set(Set<String> value) => state = value;

  void toggle(String field) {
    final next = Set<String>.of(state);
    if (!next.remove(field)) next.add(field);
    state = next;
  }
}

/// Suggestion keys the grouping notice was dismissed with. The notice hides
/// while the current suggestion keys equal these; any change shows it again.
/// Stored as a string list; a missing key means it was never dismissed.
@riverpod
class DismissedSuggestionNotice extends _$DismissedSuggestionNotice
    with PrefsMixin<Set<String>> {
  @override
  Set<String> build() {
    persistOnChange((next) async => prefs.setStringList(
        keys.PrefKey.dismissedSuggestionNotice.key, next.toList()));
    final raw = prefs.get(keys.PrefKey.dismissedSuggestionNotice.key);
    if (raw is! List || raw.any((e) => e is! String)) return {};
    return raw.cast<String>().toSet();
  }

  void dismiss(Set<String> keys) => state = keys;
}
