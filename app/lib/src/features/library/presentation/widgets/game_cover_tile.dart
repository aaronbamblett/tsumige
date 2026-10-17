// Copyright (c) 2022 Contributors to the Suwayomi project
// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../core/format.dart';
import '../../../../core/model.dart';
import '../../../../utils/theme/brand.dart';
import '../../data/library_repository.dart';
import '../../domain/cover_source.dart';
import '../../domain/selection.dart';
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
    final settledPhysical =
        settled * MediaQuery.devicePixelRatioOf(context);
    final source = coverSourceFor(game, dir, settledPhysical, exists);
    final selected = ref.watch(selectedGameIdProvider) == game.id;
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: const BorderRadius.all(Radius.circular(12)),
      onTap: () =>
          ref.read(selectedGameIdProvider.notifier).select(game.id),
      onHover: (hovered) => setState(() => _hovered = hovered),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            key: ValueKey('cover-${game.id}'),
            aspectRatio: kGameCoverAspectRatio,
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius:
                    const BorderRadius.all(Radius.circular(12)),
                border: selected
                    ? Border.all(color: colorScheme.primary, width: 3)
                    : null,
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _cover(source, settledPhysical),
                  if (game.favourite)
                    Positioned(
                      top: 4,
                      left: 4,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: OnImage.scrim,
                        ),
                        child: const Icon(
                          Icons.star_rounded,
                          size: 14,
                          color: OnImage.text,
                        ),
                      ),
                    ),
                  if (_hovered)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Padding(
                          padding: const EdgeInsets.all(1),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: const BorderRadius.all(
                                Radius.circular(11),
                              ),
                              border: Border.all(
                                color: colorScheme.primary,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          SizedBox(
            height: gameTitleBlockHeight(context),
            child: _TitleBlock(game: game),
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
            errorBuilder: (_, _, _) =>
                const Center(child: Text('No cover')),
          )
        : Image.file(
            file,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            cacheWidth: settledPhysical.round().clamp(1, 1 << 16),
            errorBuilder: (_, _, _) =>
                const Center(child: Text('No cover')),
          );
    return image;
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.game});

  final Game game;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final titleStyle =
        (textTheme.bodyMedium ?? const TextStyle(fontSize: 14)).copyWith(
      fontWeight: FontWeight.w600,
    );
    final ratingStyle =
        (textTheme.bodySmall ?? const TextStyle(fontSize: 12)).copyWith(
      color: colorScheme.onSurfaceVariant,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final rating = game.vndbRating == null
            ? null
            : formatVndbRating(game.vndbRating!);
        var showRating = rating != null;
        if (showRating) {
          final probe = TextPainter(
            text: TextSpan(text: rating, style: ratingStyle),
            textScaler: MediaQuery.textScalerOf(context),
            maxLines: 1,
            textDirection: Directionality.of(context),
          )..layout(maxWidth: constraints.maxWidth);
          showRating = !probe.didExceedMaxLines;
        }
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                game.title,
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
                style: titleStyle,
              ),
              if (showRating)
                Text(
                  rating!,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: ratingStyle,
                ),
            ],
          ),
        );
      },
    );
  }
}
