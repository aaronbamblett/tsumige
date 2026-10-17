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
///
/// The grid, the scrollbar track and the detail pane share one 12 px top
/// inset. Only the track is inset: the covers still scroll all the way up
/// to the toolbar.
class LibraryGrid extends HookConsumerWidget {
  const LibraryGrid({super.key, required this.games});

  final List<Game> games;

  /// Inset shared by the grid's top padding, the scrollbar track's top and
  /// the detail pane's top margin.
  static const topInset = 12.0;

  /// Scrollbar thumb thickness. With the 20 px grid padding this leaves at
  /// least 8 px between the last cover column and the thumb.
  static const scrollbarThickness = 8.0;

  /// Breathing room between the scrollbar and whatever is right of the grid:
  /// the detail pane when open, the window edge when closed.
  static const trailingGap = 8.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coverWidth = ref.watch(coverWidthProvider);
    final scrollController = useScrollController();
    return Padding(
      padding: const EdgeInsets.only(right: trailingGap),
      child: ScrollbarTheme(
        data: const ScrollbarThemeData(
          thickness: WidgetStatePropertyAll(scrollbarThickness),
          mainAxisMargin: topInset,
        ),
        child: Scrollbar(
          controller: scrollController,
          thumbVisibility: true,
          child: GridView.builder(
            controller: scrollController,
            padding: const EdgeInsets.only(
              top: topInset,
              left: 20,
              right: 20,
              bottom: 20,
            ),
            gridDelegate: GameCoverGridDelegate(
              maxCrossAxisExtent: coverWidth.toDouble(),
              crossAxisSpacing: 20,
              mainAxisSpacing: 24,
              titleExtent: gameTitleBlockHeight(context),
            ),
            itemCount: games.length,
            itemBuilder: (context, index) =>
                GameCoverTile(game: games[index]),
          ),
        ),
      ),
    );
  }
}
