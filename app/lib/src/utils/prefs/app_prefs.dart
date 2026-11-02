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

/// Tags the library is filtered to; a game matches when it carries any of
/// them. Empty means no include filter.
@riverpod
class TagInclude extends _$TagInclude with PrefsMixin<List<String>> {
  @override
  List<String> build() {
    persistOnChange(
      (next) async => prefs.setStringList(keys.PrefKey.tagInclude.key, next),
    );
    final stored = prefs.getStringList(keys.PrefKey.tagInclude.key);
    if (stored != null) return stored;
    final legacy = prefs.getString(keys.PrefKey.tagFilter.key);
    if (legacy == null) return const [];
    if (legacy.isEmpty) {
      prefs.remove(keys.PrefKey.tagFilter.key);
      return const [];
    }
    prefs.setStringList(keys.PrefKey.tagInclude.key, [legacy]);
    prefs.remove(keys.PrefKey.tagFilter.key);
    return [legacy];
  }

  void set(List<String> value) => state = value;

  /// Adds [tag] to the include list, removing it from exclude first; an
  /// already included tag is unchanged.
  void include(String tag) {
    if (state.contains(tag)) return;
    final exclude = ref.read(tagExcludeProvider);
    if (exclude.contains(tag)) {
      ref.read(tagExcludeProvider.notifier).set([
        for (final t in exclude)
          if (t != tag) t,
      ]);
    }
    state = [...state, tag];
  }

  /// Cycles [tag] off, include, exclude and back to off.
  void cycle(String tag) {
    final exclude = ref.read(tagExcludeProvider);
    if (exclude.contains(tag)) {
      ref.read(tagExcludeProvider.notifier).set([
        for (final t in exclude)
          if (t != tag) t,
      ]);
    } else if (state.contains(tag)) {
      state = [
        for (final t in state)
          if (t != tag) t,
      ];
      ref.read(tagExcludeProvider.notifier).set([...exclude, tag]);
    } else {
      state = [...state, tag];
    }
  }
}

/// Tags that remove a game from the library even when it matches an include
/// tag. A tag is never in both lists.
@riverpod
class TagExclude extends _$TagExclude with PrefsMixin<List<String>> {
  @override
  List<String> build() {
    persistOnChange(
      (next) async => prefs.setStringList(keys.PrefKey.tagExclude.key, next),
    );
    final include = ref.read(tagIncludeProvider);
    final stored = prefs.getStringList(keys.PrefKey.tagExclude.key) ?? const [];
    return [
      for (final tag in stored)
        if (!include.contains(tag)) tag,
    ];
  }

  void set(List<String> value) => state = value;
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
