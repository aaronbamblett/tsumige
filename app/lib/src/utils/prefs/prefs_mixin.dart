// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../constants/pref_keys.dart';
import '../../core/model.dart' as core;

part 'prefs_mixin.g.dart';

/// The shared_preferences instance. Overridden with the real instance in
/// `main()` and with a mock in tests.
@Riverpod(keepAlive: true)
SharedPreferences sharedPreferences(Ref ref) =>
    throw UnimplementedError('sharedPreferencesProvider must be overridden');

/// A mixin that persists a notifier's state to shared_preferences.
///
/// The notifier reads its [PrefKey] in `build` and calls [persistOnChange] so
/// every later state change is written back. Nullable state (such as the tag
/// filter) is supported: a null value removes the key.
mixin PrefsMixin<T> {
  Ref get ref;
  set state(T newState);
  T get state;

  /// Satisfied by the Notifier this mixes into — Riverpod 3 moved listenSelf
  /// off Ref onto the notifier itself. The return type matches Riverpod's
  /// `RemoveListener` typedef (`void Function()`), which the public barrels
  /// do not export, so it is spelled out.
  void Function() listenSelf(
    void Function(T? previous, T next) listener, {
    void Function(Object error, StackTrace stackTrace)? onError,
  });

  SharedPreferences get prefs => ref.watch(sharedPreferencesProvider);

  void persistOnChange(Future<bool> Function(T next) save) {
    listenSelf((_, next) => save(next));
  }

  int initInt(PrefKey key) {
    final fallback = key.defaultValue as int;
    persistOnChange((next) async => prefs.setInt(key.key, next as int));
    return prefs.getInt(key.key) ?? fallback;
  }

  bool initBool(PrefKey key) {
    final fallback = key.defaultValue as bool;
    persistOnChange((next) async => prefs.setBool(key.key, next as bool));
    return prefs.getBool(key.key) ?? fallback;
  }

  String initStringWithDefault(PrefKey key) {
    final fallback = key.defaultValue as String;
    persistOnChange((next) async => prefs.setString(key.key, next as String));
    return prefs.getString(key.key) ?? fallback;
  }

  String? initString(PrefKey key) {
    persistOnChange((next) async {
      final value = next as String?;
      if (value == null) return prefs.remove(key.key);
      return prefs.setString(key.key, value);
    });
    return prefs.getString(key.key);
  }

  SortField initSortField() {
    persistOnChange((next) async =>
        prefs.setInt(PrefKey.sortField.key, (next as SortField).index));
    final stored = prefs.getInt(PrefKey.sortField.key);
    if (stored != null && stored >= 0 && stored < SortField.values.length) {
      return SortField.values[stored];
    }
    return SortField.added;
  }

  core.LaunchMode initLaunchMode() {
    persistOnChange((next) async =>
        prefs.setString(PrefKey.launchMode.key, (next as core.LaunchMode).name));
    return core.parseLaunchMode(prefs.getString(PrefKey.launchMode.key)) ??
        core.LaunchMode.proton;
  }
}
