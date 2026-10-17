// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/model.dart';

part 'launch_actions.g.dart';

class LaunchActions {
  const LaunchActions();

  void launch(Game game) {}

  void runExeInPrefix(Game game) {}
}

@riverpod
LaunchActions launchActions(Ref ref) => const LaunchActions();
