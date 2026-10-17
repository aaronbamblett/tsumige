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
import '../../data/library_repository.dart';
import '../../domain/cover_source.dart';
import '../../domain/selection.dart';
import 'game_cover_grid_delegate.dart';

/// One library tile: cover, title, favourite star, up to 3 tags and the
/// VNDB rating. The image follows the settled width only, so slider drags
/// scale the current bitmap instead of re-decoding.
class GameCoverTile extends ConsumerWidget {
  const GameCoverTile({super.key, required this.game});

  final Game game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        side: BorderSide(
          color: selected ? colorScheme.primary : colorScheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: () =>
            ref.read(selectedGameIdProvider.notifier).select(game.id),
        // Both heights are fixed so the cover never depends on the text.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _cover(context, source, settledPhysical),
            SizedBox(height: kGridTitleExtent, child: _info(context)),
          ],
        ),
      ),
    );
  }

  Widget _cover(
      BuildContext context, CoverSource? source, double settledPhysical) {
    if (source == null) {
      return SizedBox(
        key: ValueKey('cover-${game.id}'),
        width: double.infinity,
        child: const AspectRatio(
          aspectRatio: kGameCoverAspectRatio,
          child: Center(child: Text('No cover')),
        ),
      );
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
    return SizedBox(
      key: ValueKey('cover-${game.id}'),
      width: double.infinity,
      child: AspectRatio(
        aspectRatio: kGameCoverAspectRatio,
        child: image,
      ),
    );
  }

  Widget _info(BuildContext context) {
    final tags = game.tags.take(3).join(', ');
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            game.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, height: 1.5),
          ),
          Row(
            children: [
              if (game.favourite)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(Icons.star_rounded, size: 14),
                ),
              Expanded(
                child: Text(
                  tags,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
          if (game.vndbRating != null)
            Text(
              formatVndbRating(game.vndbRating!),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11),
            ),
        ],
      ),
    );
  }
}
