// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

/// Library sort orders.
enum SortField { added, title, lastPlayed, playtime, vndbRating }

/// Cover grid tile width bounds, in logical pixels.
const int coverWidthMin = 100;
const int coverWidthMax = 999;
const int coverWidthDefault = 192;

/// Clamp a cover width into [coverWidthMin]..[coverWidthMax].
int clampCoverWidth(int value) => value.clamp(coverWidthMin, coverWidthMax);

/// Shared-preferences keys with their defaults.
enum PrefKey {
  coverWidth('library.coverWidth', coverWidthDefault),
  sortField('library.sortField', 0),
  sortAscending('library.sortAscending', true),
  favouritesOnly('library.favouritesOnly', false),
  tagFilter('library.tagFilter', null),
  launchMode('launch.mode', 'proton'),
  launchPrefix('launch.prefix', '~/Games/vnl/prefix'),
  launchRunner('launch.runner', null),
  launchLocale('launch.locale', 'ja_JP.UTF-8'),
  launchUmuGameId('launch.umuGameId', 'umu-default'),
  windowWidth('window.width', null),
  windowHeight('window.height', null),
  windowMaximized('window.maximized', false);

  const PrefKey(this.key, this.defaultValue);

  /// The string key stored in shared_preferences. The window keys match the
  /// keys in `window_geometry_store.dart`.
  final String key;
  final Object? defaultValue;
}
