// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/group_detection.dart';
import '../../../utils/prefs/app_prefs.dart';
import '../data/library_repository.dart';

part 'group_suggestions.g.dart';

/// Episode-group suggestions the user hasn't marked "Not a series".
@riverpod
List<GroupSuggestion> groupSuggestions(Ref ref) {
  final library = ref.watch(libraryProvider).value?.library;
  if (library == null) return const [];
  return suggestGroups(
    library,
    dismissed: library.dismissedGroupSuggestions,
  );
}

/// The suggestions the notice shows: none while the current suggestion keys
/// equal the keys the notice was last dismissed with. Any change — a new
/// suggestable game, a grouping, a "Not a series" — shows it again.
@riverpod
List<GroupSuggestion> visibleGroupSuggestions(Ref ref) {
  final suggestions = ref.watch(groupSuggestionsProvider);
  if (suggestions.isEmpty) return const [];
  final dismissed = ref.watch(dismissedSuggestionNoticeProvider);
  final keys = {for (final s in suggestions) s.key};
  if (keys.length == dismissed.length && keys.containsAll(dismissed)) {
    return const [];
  }
  return suggestions;
}
