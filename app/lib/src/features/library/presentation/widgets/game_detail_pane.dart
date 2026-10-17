// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../../../../core/covers.dart';
import '../../../../core/format.dart';
import '../../../../core/model.dart';
import '../../data/library_repository.dart';
import '../../domain/cover_source.dart';
import '../../domain/selection.dart';
import '../../domain/vndb_markup.dart';
import 'game_cover_grid_delegate.dart';

/// Detail pane for the selected game: title, cover, VNDB rating, release
/// date, tags, description, playtime, sessions and routes.
class GameDetailPane extends ConsumerWidget {
  const GameDetailPane({super.key, required this.game});

  final Game game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxCoverHeight = constraints.maxHeight * 0.4;
        final contentWidth = constraints.maxWidth;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 0, 0),
                    child: Text(
                      game.title,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => ref
                      .read(selectedGameIdProvider.notifier)
                      .clear(),
                ),
              ],
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 12,
                  children: [
                    _cover(context, ref, maxCoverHeight, contentWidth - 32),
                    if (game.vndbRating != null)
                      Text(
                        game.vndbVotecount == null
                            ? formatVndbRating(game.vndbRating!)
                            : '${formatVndbRating(game.vndbRating!)} '
                                '(${game.vndbVotecount} votes)',
                      ),
                    if (game.released != null && game.released!.isNotEmpty)
                      Text('Released ${game.released!}'),
                    if (game.tags.isNotEmpty)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final tag in game.tags) Chip(label: Text(tag)),
                        ],
                      ),
                    if (game.description.isNotEmpty) ...[
                      _heading(context, 'Description'),
                      VndbMarkupText(text: game.description),
                    ],
                    _heading(context, 'Play time'),
                    Text(
                      'Total playtime '
                      '${formatPlaytime(game.totalPlaytimeSeconds)}',
                    ),
                    for (final session in _newestFirst(game.playSessions))
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              DateFormat('yyyy-MM-dd HH:mm').format(
                                session.startedAt.toLocal(),
                              ),
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                          Text(
                            formatPlaytime(session.durationSeconds),
                            textAlign: TextAlign.right,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    if (game.routes.isNotEmpty) ...[
                      _heading(context, 'Routes'),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 4,
                        children: [
                          for (final route in game.routes)
                            Row(
                              children: [
                                Expanded(child: Text(route.name)),
                                if (route.completed)
                                  const Icon(Icons.check_rounded),
                                if (route.name == game.activeRoute)
                                  const Padding(
                                    padding: EdgeInsets.only(left: 8),
                                    child: Text('Active'),
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _heading(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.titleSmall
          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
    );
  }

  List<PlaySession> _newestFirst(List<PlaySession> sessions) {
    final sorted = sessions.toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return sorted;
  }

  Widget _cover(BuildContext context, WidgetRef ref, double maxHeight,
      double width) {
    final cover = game.cover;
    if (cover == null || cover.isEmpty) return const SizedBox.shrink();
    var coverWidth = width;
    var coverHeight = coverWidth / kGameCoverAspectRatio;
    if (coverHeight > maxHeight) {
      coverHeight = maxHeight;
      coverWidth = coverHeight * kGameCoverAspectRatio;
    }
    final dir = ref.watch(dataDirProvider);
    final exists = ref.watch(coverExistsProvider);
    final thumb = thumbPath(dir, game.id, 512);
    // The thumbnail paints first; the original fades in over it with no gap.
    final physicalWidth =
        (coverWidth * MediaQuery.devicePixelRatioOf(context)).round().clamp(
      1,
      1 << 16,
    );
    final original = File(p.join(dir.coversOriginal.path, cover));
    return Center(
      child: SizedBox(
        width: coverWidth,
        height: coverHeight,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (exists(thumb))
              Image.file(
                File(thumb),
                fit: BoxFit.contain,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            Image.file(
              original,
              fit: BoxFit.contain,
              gaplessPlayback: true,
              cacheWidth: physicalWidth,
              frameBuilder: (context, child, frame, _) =>
                  frame == null ? const SizedBox.shrink() : child,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}
