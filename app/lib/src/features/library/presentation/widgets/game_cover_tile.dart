// Copyright (c) 2022 Contributors to the Suwayomi project
// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../core/model.dart';
import '../../data/library_repository.dart';
import '../../domain/cover_source.dart';
import '../../domain/selection.dart';
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

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final dir = ref.watch(dataDirProvider);
    final exists = ref.watch(coverExistsProvider);
    final settled = ref.watch(settledCoverWidthProvider);
    final settledPhysical = settled * MediaQuery.devicePixelRatioOf(context);
    final source = coverSourceFor(game, dir, settledPhysical, exists);
    final selected = ref.watch(selectedGameIdProvider) == game.id;
    final colorScheme = Theme.of(context).colorScheme;
    const coverRadius = BorderRadius.all(Radius.circular(10));
    return InkWell(
      borderRadius: coverRadius,
      onTap: () {
        final selection = ref.read(selectedGameIdProvider.notifier);
        if (selected) {
          selection.clear();
        } else {
          selection.select(game.id);
        }
      },
      onHover: (hovered) => setState(() => _hovered = hovered),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            key: ValueKey('cover-${game.id}'),
            aspectRatio: kGameCoverAspectRatio,
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: const BoxDecoration(borderRadius: coverRadius),
              foregroundDecoration: selected || _hovered
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
                  _cover(source, settledPhysical),
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

  Widget _cover(CoverSource? source, double settledPhysical) {
    if (source == null) {
      return const Center(child: Text('No cover'));
    }
    final file = File(source.path);
    // Thumbnails decode at their own size, keeping a stable image-cache key
    // while the slider moves. Only the original decodes at the settled width.
    final image = source.isThumbnail
        ? Image.file(
            file,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => const Center(child: Text('No cover')),
          )
        : Image.file(
            file,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            cacheWidth: settledPhysical.round().clamp(1, 1 << 16),
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
