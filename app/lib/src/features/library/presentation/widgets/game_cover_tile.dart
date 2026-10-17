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
  const GameCoverTile({super.key, required this.game});

  final Game game;

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
    final selected = ref.watch(selectedGameIdProvider) == game.id;
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
      onTap: () {
        setState(() => _pointerFocused = true);
        _focusNode.requestFocus();
        final selection = ref.read(selectedGameIdProvider.notifier);
        if (selected) {
          selection.clear();
        } else {
          selection.select(game.id);
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
                  if (game.favourite)
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
            child: _TitleBlock(game: game, selected: selected),
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
    final image = source.isThumbnail
        ? Image(
            image: artFileImage(file, version: version(source.path)),
            fit: BoxFit.cover,
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

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.game, required this.selected});

  final Game game;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        game.title,
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
