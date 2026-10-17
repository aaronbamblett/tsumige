// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/launch/game_runner.dart';

part 'running_games.g.dart';

/// The launch phase of each game vnl can currently see.
///
/// Entries exist only between `starting` and `ended`: the `ended` callback
/// removes the game, so the button shows "Running" (or "Launching…") only
/// while the game's process is actually visible. Keep-alive: a launch
/// outlives the detail pane, and the entry must still be here when the game
/// exits, even if the pane was closed and reopened mid-session.
@Riverpod(keepAlive: true)
class RunningGames extends _$RunningGames {
  @override
  Map<String, LaunchPhase> build() => const {};

  void setPhase(String id, LaunchPhase phase) {
    if (phase == LaunchPhase.ended) {
      remove(id);
      return;
    }
    if (state[id] == phase) return;
    state = {...state, id: phase};
  }

  void add(String id) => setPhase(id, LaunchPhase.starting);

  void remove(String id) {
    if (!state.containsKey(id)) return;
    state = {...state}..remove(id);
  }
}
