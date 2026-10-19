// Copyright (c) 2022 Contributors to the Suwayomi project
// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Game covers are portrait art; 2:3 fits the library's covers.
const kGameCoverAspectRatio = 2 / 3;

/// 8 px of padding between the cover and the title.
const double _kTitleTopPadding = 8;

/// Title type under each cover: 14 px, two lines at a 1.3 line height.
const double kGameTitleFontSize = 14;
const double kGameTitleHeight = 1.3;

/// Height of the fixed title block under a cover at the current platform text
/// scale: two title lines, so tiles with 1-line titles keep the same cover size
/// as tiles with 2-line titles.
double gameTitleBlockHeight(BuildContext context) {
  final scaler = MediaQuery.textScalerOf(context);
  return _kTitleTopPadding +
      scaler.scale(kGameTitleFontSize) * kGameTitleHeight * 2;
}

/// Row height follows the column width, so the cover stays 2:3.
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
  final childMainAxisExtent =
      childCrossAxisExtent / kGameCoverAspectRatio + titleExtent;
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
    this.mainAxisSpacing = 24.0,
    this.crossAxisSpacing = 20.0,
    this.titleExtent = 0.0,
  }) : assert(maxCrossAxisExtent > 0);

  final double maxCrossAxisExtent;
  final double mainAxisSpacing;
  final double crossAxisSpacing;
  final double titleExtent;

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) => _coverTileLayout(
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
    this.mainAxisSpacing = 24.0,
    this.crossAxisSpacing = 20.0,
    this.titleExtent = 0.0,
  }) : assert(crossAxisCount > 0);

  final int crossAxisCount;
  final double mainAxisSpacing;
  final double crossAxisSpacing;
  final double titleExtent;

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) => _coverTileLayout(
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
