// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

/// Fixed overlay colours drawn over cover art. They stay the same in every
/// theme because the art underneath does not change; icons use [OnImage].
abstract final class ArtOverlay {
  /// Favourite badge on a cover: rgba(13,11,22,.72).
  static const badge = Color(0xB80D0B16);

  /// Pane circle buttons: rgba(13,11,22,.78), and .92 on hover.
  static const button = Color(0xC70D0B16);
  static const buttonHover = Color(0xEB0D0B16);

  /// Top scrim behind the pane title: rgba(13,11,22,.70).
  static const scrimTop = Color(0xB30D0B16);

  /// White rings: 16% on the badge, 22% on pane buttons, 40% on hover.
  static const badgeRing = Color(0x29FFFFFF);
  static const buttonRing = Color(0x38FFFFFF);
  static const buttonRingHover = Color(0x66FFFFFF);

  /// Pane button drop shadow: 0 2 8 rgba(0,0,0,.45).
  static const buttonShadow = [
    BoxShadow(color: Color(0x73000000), offset: Offset(0, 2), blurRadius: 8),
  ];
}
