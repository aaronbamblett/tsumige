// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../core/model.dart';
import '../../../../utils/prefs/app_prefs.dart';
import 'game_cover_grid_delegate.dart';
import 'game_cover_tile.dart';

/// Lazy cover grid. The column width follows the slider live; the covers
/// themselves follow the settled width (see [GameCoverTile]).
class LibraryGrid extends HookConsumerWidget {
  const LibraryGrid({super.key, required this.games});

  final List<Game> games;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coverWidth = ref.watch(coverWidthProvider);
    final scrollController = useScrollController();
    return Scrollbar(
      controller: scrollController,
      thumbVisibility: true,
      child: GridView.builder(
        controller: scrollController,
        padding: const EdgeInsets.all(8),
        gridDelegate: GameCoverGridDelegate(
          maxCrossAxisExtent: coverWidth.toDouble(),
        ),
        itemCount: games.length,
        itemBuilder: (context, index) =>
            GameCoverTile(game: games[index]),
      ),
    );
  }
}
