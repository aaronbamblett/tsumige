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
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        side: selected
            ? BorderSide(color: colorScheme.primary, width: 3)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: () =>
            ref.read(selectedGameIdProvider.notifier).select(game.id),
        onHover: (hovered) => setState(() => _hovered = hovered),
        child: AspectRatio(
          key: ValueKey('cover-${game.id}'),
          aspectRatio: kGameCoverAspectRatio,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _cover(source, settledPhysical),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _overlay(context),
              ),
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
    return Container(
      foregroundDecoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment(0, 1 / 3),
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, OnImage.scrim],
        ),
      ),
      child: image,
    );
  }

  Widget _overlay(BuildContext context) {
    final game = widget.game;
    return LayoutBuilder(
      builder: (context, constraints) {
        final rating = game.vndbRating == null
            ? null
            : formatVndbRating(game.vndbRating!);
        const ratingStyle = TextStyle(
          color: OnImage.text,
          fontSize: 11,
          shadows: [Shadow(color: OnImage.shadow, blurRadius: 4)],
        );
        var showRating = rating != null;
        if (showRating) {
          final probe = TextPainter(
            text: TextSpan(text: rating, style: ratingStyle),
            textScaler: MediaQuery.textScalerOf(context),
            maxLines: 1,
            textDirection: Directionality.of(context),
          )..layout(maxWidth: constraints.maxWidth - 16);
          showRating = !probe.didExceedMaxLines;
        }
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          dense: true,
          title: Text(
            game.title,
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
            style: const TextStyle(
              color: OnImage.text,
              fontSize: 12,
              height: 1.5,
              shadows: [Shadow(color: OnImage.shadow, blurRadius: 4)],
            ),
          ),
          subtitle: showRating
              ? Text(
                  rating!,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: ratingStyle,
                )
              : null,
        );
      },
    );
  }
}
