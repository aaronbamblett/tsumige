// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'running_games.g.dart';

/// The ids of games running right now. A second game can launch while one
/// runs, so this is a set rather than a single id.
@riverpod
class RunningGames extends _$RunningGames {
  @override
  Set<String> build() => const {};

  void add(String id) => state = {...state, id};

  void remove(String id) {
    if (!state.contains(id)) return;
    state = state.where((other) => other != id).toSet();
  }
}
