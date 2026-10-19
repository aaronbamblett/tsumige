// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

/// Library sort orders.
enum SortField { added, title, lastPlayed, playtime, vndbRating }

/// Toolbar filter on adult games.
enum AdultFilter { all, hide, only }

/// Cover grid tile width bounds, in logical pixels.
const int coverWidthMin = 100;
const int coverWidthMax = 400;
const int coverWidthDefault = 192;

/// Clamp a cover width into [coverWidthMin]..[coverWidthMax].
int clampCoverWidth(int value) => value.clamp(coverWidthMin, coverWidthMax);

/// Info tab sections the details panel may show. Stored as a string list;
/// a missing key or any unknown entry means every field is shown.
const String detailFieldDescription = 'description';
const String detailFieldTags = 'tags';
const String detailFieldVndbTags = 'vndbTags';
const String detailFieldNotes = 'notes';

const Set<String> detailFieldsAll = {
  detailFieldDescription,
  detailFieldTags,
  detailFieldVndbTags,
  detailFieldNotes,
};

/// Shared-preferences keys with their defaults.
enum PrefKey {
  coverWidth('library.coverWidth', coverWidthDefault),
  sortField('library.sortField', 0),
  sortAscending('library.sortAscending', true),
  favouritesOnly('library.favouritesOnly', false),
  adultFilter('library.adultFilter', 0),
  tagFilter('library.tagFilter', null),
  dismissedSuggestionNotice('library.dismissedSuggestionNotice', null),
  launchPrefix('launch.prefix', '~/Games/tsumige/prefix'),
  launchRunner('launch.runner', null),
  launchLocale('launch.locale', 'ja_JP.UTF-8'),
  launchUmuGameId('launch.umuGameId', 'umu-default'),
  detailFields('appearance.detailFields', null),
  windowWidth('window.width', null),
  windowHeight('window.height', null),
  windowMaximized('window.maximized', false),
  appTheme('appearance.appTheme', null),
  themeMode('appearance.themeMode', null),
  customThemeColor('appearance.customColor', null),
  steamGridDbKey('artSources.steamGridDbKey', '');

  const PrefKey(this.key, this.defaultValue);

  /// The string key stored in shared_preferences. The window keys match the
  /// keys in `window_geometry_store.dart`.
  final String key;
  final Object? defaultValue;
}
