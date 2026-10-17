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
                _hero(context, ref),
                if (game.description.isNotEmpty) ...[
                  _heading(context, 'Description'),
                  VndbMarkupText(text: game.description),
                ],
                ..._sessionRows(context),
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

  List<Widget> _sessionRows(BuildContext context) {
    final sessions = _newestFirst(game.playSessions);
    if (sessions.isEmpty) return const [];
    return [
      _heading(context, 'Sessions'),
      for (final session in sessions)
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
    ];
  }

  Widget _hero(BuildContext context, WidgetRef ref) {
    final cover = game.cover;
    if (cover == null || cover.isEmpty) return _facts(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heroCover(context, ref),
        const SizedBox(width: 12),
        Expanded(child: _facts(context)),
      ],
    );
  }

  Widget _facts(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.labelMedium
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 10,
      children: [
        if (game.vndbRating != null) ...[
          Text('VNDB Rating', style: labelStyle),
          Text(
            (game.vndbRating! / 10).toStringAsFixed(1),
            style: theme.textTheme.headlineSmall,
          ),
          if (game.vndbVotecount != null)
            Text(
              '${game.vndbVotecount} votes',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
        if (game.released != null && game.released!.isNotEmpty) ...[
          Text('Released', style: labelStyle),
          Text(game.released!, style: theme.textTheme.bodyLarge),
        ],
        Text('Total playtime', style: labelStyle),
        Text(
          formatPlaytime(game.totalPlaytimeSeconds),
          style: theme.textTheme.bodyLarge,
        ),
        if (game.tags.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final tag in game.tags)
                Chip(
                  label: Text(tag),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
            ],
          ),
      ],
    );
  }

  Widget _heroCover(BuildContext context, WidgetRef ref) {
    const width = 190.0;
    final dir = ref.watch(dataDirProvider);
    final exists = ref.watch(coverExistsProvider);
    final thumb = thumbPath(dir, game.id, 512);
    // The thumbnail paints first; the original fades in over it with no gap.
    final physicalWidth =
        (width * MediaQuery.devicePixelRatioOf(context)).round().clamp(
      1,
      1 << 16,
    );
    final original = File(p.join(dir.coversOriginal.path, game.cover!));
    return SizedBox(
      key: const ValueKey('detail-cover'),
      width: width,
      child: AspectRatio(
        aspectRatio: kGameCoverAspectRatio,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (exists(thumb))
                Image.file(
                  File(thumb),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              Image.file(
                original,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                cacheWidth: physicalWidth,
                frameBuilder: (context, child, frame, _) =>
                    frame == null ? const SizedBox.shrink() : child,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
