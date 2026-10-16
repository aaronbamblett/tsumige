// Copyright (c) 2022 Contributors to the Suwayomi project
// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:math';

import 'package:flutter/rendering.dart';

/// Game covers are portrait art; 3:4 fits the library's covers.
const kGameCoverAspectRatio = 3 / 4;

/// Height reserved for the title, tags and rating lines under a grid cover.
const kGridTitleExtent = 84.0;

/// Total inset the tile's Card takes out of each axis — Flutter's default card
/// margin of 4 on all four sides. The cell is grown by this so the artwork
/// inside the card, not the cell, is what ends up at 3:4.
const kGameCoverCardInset = 8.0;

/// Row height comes from the resolved column width, so the cover keeps its 3:4
/// shape at every column count.
SliverGridRegularTileLayout _coverTileLayout(
  SliverConstraints constraints, {
  required int crossAxisCount,
  required double crossAxisSpacing,
  required double mainAxisSpacing,
  required double titleExtent,
}) {
  final usableCrossAxisExtent = max(
    0.0,
    constraints.crossAxisExtent - crossAxisSpacing * (crossAxisCount - 1),
  );
  final childCrossAxisExtent = usableCrossAxisExtent / crossAxisCount;
  final coverWidth = max(0.0, childCrossAxisExtent - kGameCoverCardInset);
  final childMainAxisExtent = coverWidth / kGameCoverAspectRatio +
      kGameCoverCardInset +
      titleExtent;
  return SliverGridRegularTileLayout(
    crossAxisCount: crossAxisCount,
    mainAxisStride: childMainAxisExtent + mainAxisSpacing,
    crossAxisStride: childCrossAxisExtent + crossAxisSpacing,
    childMainAxisExtent: childMainAxisExtent,
    childCrossAxisExtent: childCrossAxisExtent,
    reverseCrossAxis: axisDirectionIsReversed(constraints.crossAxisDirection),
  );
}

/// Width-driven columns (the library layout: the slider sets the max width).
class GameCoverGridDelegate extends SliverGridDelegate {
  const GameCoverGridDelegate({
    required this.maxCrossAxisExtent,
    this.mainAxisSpacing = 8.0,
    this.crossAxisSpacing = 8.0,
    this.titleExtent = kGridTitleExtent,
  }) : assert(maxCrossAxisExtent > 0);

  final double maxCrossAxisExtent;
  final double mainAxisSpacing;
  final double crossAxisSpacing;
  final double titleExtent;

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) =>
      _coverTileLayout(
        constraints,
        crossAxisCount: max(
          1,
          (constraints.crossAxisExtent / (maxCrossAxisExtent + crossAxisSpacing))
              .ceil(),
        ),
        crossAxisSpacing: crossAxisSpacing,
        mainAxisSpacing: mainAxisSpacing,
        titleExtent: titleExtent,
      );

  @override
  bool shouldRelayout(GameCoverGridDelegate oldDelegate) =>
      oldDelegate.maxCrossAxisExtent != maxCrossAxisExtent ||
      oldDelegate.mainAxisSpacing != mainAxisSpacing ||
      oldDelegate.crossAxisSpacing != crossAxisSpacing ||
      oldDelegate.titleExtent != titleExtent;
}

/// Fixed column count.
class GameCoverFixedCountGridDelegate extends SliverGridDelegate {
  const GameCoverFixedCountGridDelegate({
    required this.crossAxisCount,
    this.mainAxisSpacing = 8.0,
    this.crossAxisSpacing = 8.0,
    this.titleExtent = kGridTitleExtent,
  }) : assert(crossAxisCount > 0);

  final int crossAxisCount;
  final double mainAxisSpacing;
  final double crossAxisSpacing;
  final double titleExtent;

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) =>
      _coverTileLayout(
        constraints,
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: crossAxisSpacing,
        mainAxisSpacing: mainAxisSpacing,
        titleExtent: titleExtent,
      );

  @override
  bool shouldRelayout(GameCoverFixedCountGridDelegate oldDelegate) =>
      oldDelegate.crossAxisCount != crossAxisCount ||
      oldDelegate.mainAxisSpacing != mainAxisSpacing ||
      oldDelegate.crossAxisSpacing != crossAxisSpacing ||
      oldDelegate.titleExtent != titleExtent;
}
