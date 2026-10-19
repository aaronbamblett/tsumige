// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../domain/library_query.dart';
import '../../domain/selection.dart';
import '../../../../utils/prefs/app_prefs.dart';
import 'game_cover_grid_delegate.dart';
import 'game_cover_tile.dart';

/// Lazy cover grid. The column width follows the slider live; the covers
/// themselves follow the settled width (see [GameCoverTile]).
///
/// The grid viewport starts 12 px below the toolbar, on the same line as
/// the detail pane's top edge, and scrolled content is clipped there:
/// nothing renders in the 12 px band above the viewport.
class LibraryGrid extends HookConsumerWidget {
  const LibraryGrid({super.key, required this.tiles});

  final List<LibraryTile> tiles;

  /// Inset shared by the grid viewport's top, the scrollbar track's top
  /// and the detail pane's top margin.
  static const topInset = 12.0;

  /// Cover columns end this far inside the viewport's left and right edges;
  /// the scrollbar sits in the right inset. The toolbar aligns to the right one.
  static const horizontalPadding = 20.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coverWidth = ref.watch(coverWidthProvider);
    final scrollController = useScrollController();
    if (tiles.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: topInset),
        child: Center(child: Text('No games match')),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: topInset),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => ref.read(selectedGameIdProvider.notifier).clear(),
        child: Scrollbar(
          controller: scrollController,
          thumbVisibility: true,
          child: GridView.builder(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(
              horizontalPadding,
              0,
              horizontalPadding,
              20,
            ),
            gridDelegate: GameCoverGridDelegate(
              maxCrossAxisExtent: coverWidth.toDouble(),
              crossAxisSpacing: 20,
              mainAxisSpacing: 24,
              titleExtent: gameTitleBlockHeight(context),
            ),
            itemCount: tiles.length,
            itemBuilder: (context, index) {
              final tile = tiles[index];
              return switch (tile) {
                SingleTile(:final game) => GameCoverTile(
                  key: ValueKey(game.id),
                  game: game,
                ),
                GroupTile(:final group, :final members) => GameCoverTile(
                  key: ValueKey(group.id),
                  game: members.first,
                  titleOverride: group.name,
                  badgeCount: members.length,
                  selectId: group.id,
                ),
              };
            },
          ),
        ),
      ),
    );
  }
}
