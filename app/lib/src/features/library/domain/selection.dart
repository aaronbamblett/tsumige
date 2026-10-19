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
