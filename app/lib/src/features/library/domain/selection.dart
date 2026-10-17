// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/model.dart';
import '../data/library_repository.dart';

part 'selection.g.dart';

/// Selected game id; null means the detail pane is closed.
@Riverpod(keepAlive: true)
class SelectedGameId extends _$SelectedGameId {
  @override
  String? build() => null;

  void select(String? id) => state = id;

  void clear() => state = null;
}

/// The selected game from the full library, so a filter hiding it leaves the
/// pane open while a reload that drops its id closes the pane.
@riverpod
Game? selectedGame(Ref ref) {
  final id = ref.watch(selectedGameIdProvider);
  if (id == null) return null;
  final games = ref.watch(libraryProvider).value?.library.games;
  if (games == null) return null;
  for (final game in games) {
    if (game.id == id) return game;
  }
  return null;
}
