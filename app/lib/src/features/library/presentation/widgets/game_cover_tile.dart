// Copyright (c) 2022 Contributors to the Suwayomi project
// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../core/model.dart';
import '../../data/library_repository.dart';
import '../../domain/cover_source.dart';
import '../../domain/selection.dart';
import 'art_image.dart';
import 'art_overlay.dart';
import 'game_cover_grid_delegate.dart';

class GameCoverTile extends ConsumerStatefulWidget {
  const GameCoverTile({
    super.key,
    required this.game,
    this.titleOverride,
    this.badgeCount,
    this.selectId,
  });

  final Game game;

  /// Group tiles show the group name instead of the cover member's title.
  final String? titleOverride;

  /// Group tiles show a count badge with this many members.
  final int? badgeCount;

  /// Group tiles select this id (the group) instead of the game's id.
  final String? selectId;

  @override
  ConsumerState<GameCoverTile> createState() => _GameCoverTileState();
}

class _GameCoverTileState extends ConsumerState<GameCoverTile> {
  var _hovered = false;
  var _focused = false;
  var _pointerFocused = false;
  late final _focusNode = FocusNode(onKeyEvent: _onKeyEvent);

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_onHighlightModeChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_onHighlightModeChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _onHighlightModeChanged(FocusHighlightMode mode) {
    if (_focused) setState(() {});
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (_pointerFocused && event is KeyDownEvent) {
      setState(() => _pointerFocused = false);
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final dir = ref.watch(dataDirProvider);
    final exists = ref.watch(coverExistsProvider);
    final version = ref.watch(artVersionProvider);
    final settled = ref.watch(settledCoverWidthProvider);
    final settledPhysical = settled * MediaQuery.devicePixelRatioOf(context);
    final source = coverSourceFor(game, dir, settledPhysical, exists);
    final selectId = widget.selectId ?? game.id;
    final selected =
        ref.watch(selectedGameIdProvider) == selectId ||
        ref.watch(multiSelectionProvider).contains(selectId);
    final colorScheme = Theme.of(context).colorScheme;
    const coverRadius = BorderRadius.all(Radius.circular(10));
    final keyboardFocus =
        _focused &&
        !_pointerFocused &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    return InkWell(
      borderRadius: coverRadius,
      hoverColor: Colors.transparent,
      highlightColor: Colors.transparent,
      splashColor: Colors.transparent,
      focusColor: Colors.transparent,
      focusNode: _focusNode,
      onTapDown: (_) => setState(() => _pointerFocused = true),
      onTap: () {
        _focusNode.requestFocus();
        final single = ref.read(selectedGameIdProvider.notifier);
        final multi = ref.read(multiSelectionProvider.notifier);
        if (HardwareKeyboard.instance.isShiftPressed) {
          multi.selectRangeTo(
            selectId,
            [for (final tile in ref.read(visibleTilesProvider)) tile.key],
          );
          single.select(selectId);
        } else if (HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed) {
          multi.toggle(selectId);
        } else if (ref.read(multiSelectionProvider).isEmpty &&
            ref.read(selectedGameIdProvider) == selectId) {
          single.clear();
          multi.clear();
        } else {
          multi.showSingle(selectId);
          single.select(selectId);
        }
      },
      onHover: (hovered) => setState(() => _hovered = hovered),
      onFocusChange: (focused) => setState(() {
        _focused = focused;
        if (!focused) _pointerFocused = false;
      }),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            key: ValueKey('cover-${game.id}'),
            aspectRatio: kGameCoverAspectRatio,
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: const BoxDecoration(borderRadius: coverRadius),
              foregroundDecoration: selected || _hovered || keyboardFocus
                  ? BoxDecoration(
                      borderRadius: coverRadius,
                      border: Border.all(
                        color: colorScheme.primary,
                        width: selected ? 3 : 2,
                      ),
                    )
                  : null,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _cover(source, settledPhysical, version),
                  if (widget.badgeCount != null)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: _CountBadge(count: widget.badgeCount!),
                    )
                  else if (game.favourite)
                    const Positioned(
                      top: 8,
                      right: 8,
                      child: _FavouriteBadge(),
                    ),
                ],
              ),
            ),
          ),
          SizedBox(
            height: gameTitleBlockHeight(context),
            child: _TitleBlock(
              title: widget.titleOverride ?? game.title,
              selected: selected,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cover(
    CoverSource? source,
    double settledPhysical,
    String Function(String) version,
  ) {
    if (source == null) {
      return const Center(child: Text('No cover'));
    }
    final file = File(source.path);
    // Thumbnails decode at their own size, keeping a stable image-cache key
    // while the slider moves. Only the original decodes at the settled width.
    final alignment = widget.game.coverAlignment ?? kLibraryCoverAlignment;
    final image = source.isThumbnail
        ? Image(
            image: artFileImage(file, version: version(source.path)),
            fit: BoxFit.cover,
            alignment: alignment,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => const Center(child: Text('No cover')),
          )
        : Image(
            image: artFileImage(
              file,
              version: version(source.path),
              cacheWidth: settledPhysical.round().clamp(1, 1 << 16),
            ),
            fit: BoxFit.cover,
            alignment: alignment,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => const Center(child: Text('No cover')),
          );
    return image;
  }
}

class _FavouriteBadge extends StatelessWidget {
  const _FavouriteBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ArtOverlay.badge,
        border: Border.all(color: ArtOverlay.badgeRing),
      ),
      child: Icon(
        Icons.favorite_rounded,
        size: 16,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

/// Member-count pill for a group tile: an 11 px-radius pill on the pane
/// button fill with the badge ring, a stacked-pages icon and the count in
/// 12 px semibold on-image text.
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(11),
        color: ArtOverlay.button,
        border: Border.all(color: ArtOverlay.badgeRing),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          const Icon(
            Icons.collections_bookmark_outlined,
            size: 14,
            color: Colors.white,
          ),
          Text(
            '$count',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.title, required this.selected});

  final String title;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        title,
        overflow: TextOverflow.ellipsis,
        maxLines: 2,
        style: TextStyle(
          fontSize: kGameTitleFontSize,
          height: kGameTitleHeight,
          fontWeight: FontWeight.w600,
          color: selected ? colorScheme.primary : colorScheme.onSurface,
        ),
      ),
    );
  }
}
