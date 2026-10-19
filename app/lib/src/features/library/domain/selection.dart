// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/groups.dart';
import '../../../core/model.dart';
import '../data/library_repository.dart';

part 'selection.g.dart';

/// Selected tile id: a game id, or a group id. Null means the detail pane is
/// closed. When a group is selected, the pane shows one of its members (see
/// [selectedGame]), so the selection represents "group X, showing member Y".
///
/// Selecting a game id that belongs to a group selects the group instead and
/// remembers that member, so every caller of [select] (grid, Related tab)
/// opens the group with that member shown.
@Riverpod(keepAlive: true)
class SelectedGameId extends _$SelectedGameId {
  @override
  String? build() => null;

  void select(String? id) {
    if (id == null) {
      state = id;
      return;
    }
    final groups = ref.read(libraryProvider).value?.library.groups;
    if (groups != null) {
      for (final group in groups) {
        if (group.memberIds.contains(id)) {
          group.lastPickedId = id;
          if (state == group.id) {
            // Same tile, different member: an equal assignment rebuilds
            // nothing, so bounce through null to show the newly picked one.
            state = null;
          }
          state = group.id;
          return;
        }
      }
    }
    state = id;
  }

  void clear() => state = null;
}

/// Several grid tiles selected with Ctrl/Shift for Combine. The single
/// selection ([SelectedGameId]) is untouched: while 2 or more tiles are
/// selected the pane shows a summary instead of a game.
@Riverpod(keepAlive: true)
class MultiSelection extends _$MultiSelection {
  /// The last clicked tile; a Shift+click selects the range from here.
  String? _anchor;

  @override
  List<String> build() => const [];

  /// A plain click collapses back to one tile: no multi-selection.
  void showSingle(String id) {
    _anchor = id;
    state = const [];
  }

  /// Ctrl+click toggles a tile in or out, in click order. The first one
  /// seeds the selection with the open tile, so it stays selected too.
  void toggle(String id) {
    _anchor = id;
    if (state.contains(id)) {
      state = [for (final other in state) if (other != id) other];
    } else {
      if (state.isEmpty) {
        final open = ref.read(selectedGameIdProvider);
        if (open != null && open != id) {
          state = [open, id];
          return;
        }
      }
      state = [...state, id];
    }
  }

  /// Shift+click selects the range from the last clicked tile to [id] in
  /// [orderedKeys] (the current grid order), inclusive. The anchor stays put
  /// so another Shift+click re-anchors from the same tile.
  void selectRangeTo(String id, List<String> orderedKeys) {
    final anchor = _anchor;
    final a = anchor == null ? -1 : orderedKeys.indexOf(anchor);
    final b = orderedKeys.indexOf(id);
    if (b < 0) return;
    if (a < 0) {
      _anchor = id;
      state = [id];
      return;
    }
    final from = a < b ? a : b;
    final to = a < b ? b : a;
    state = orderedKeys.sublist(from, to + 1);
  }

  void clear() {
    _anchor = null;
    state = const [];
  }
}

/// The selected group, when the selected tile is a group.
@riverpod
GameGroup? selectedGroup(Ref ref) {
  final id = ref.watch(selectedGameIdProvider);
  if (id == null) return null;
  final groups = ref.watch(libraryProvider).value?.library.groups;
  if (groups == null) return null;
  for (final group in groups) {
    if (group.id == id) return group;
  }
  return null;
}

/// The selected game from the full library, so a filter hiding it leaves the
/// pane open while a reload that drops its id closes the pane. When a group
/// is selected, this is the group's picked member.
@riverpod
Game? selectedGame(Ref ref) {
  final id = ref.watch(selectedGameIdProvider);
  if (id == null) return null;
  final library = ref.watch(libraryProvider).value?.library;
  if (library == null) return null;
  final byId = {for (final game in library.games) game.id: game};
  for (final group in library.groups) {
    if (group.id == id) return resolvePickedMember(group, byId);
  }
  return byId[id];
}
