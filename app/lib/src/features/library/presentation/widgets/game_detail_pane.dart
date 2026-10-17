// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;

import 'package:http/http.dart' as http;

import '../../../../core/covers.dart';
import '../../../../core/launch/game_runner.dart';
import '../../../../core/model.dart';
import '../../../../core/trash.dart';
import '../../../../core/vndb.dart';
import '../../../../utils/prefs/app_prefs.dart' hide LaunchMode;
import '../../../../utils/toast.dart';
import '../../data/library_repository.dart';
import '../../domain/cover_source.dart';
import '../../domain/game_editor.dart';
import '../../domain/launch_actions.dart';
import '../../domain/running_games.dart';
import '../../domain/selection.dart';
import 'detail_tabs/history_tab.dart';
import 'detail_tabs/info_tab.dart';
import 'detail_tabs/launch_tab.dart';



class GameDetailPane extends ConsumerWidget {
  const GameDetailPane({super.key, required this.game});

  final Game game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    return DefaultTabController(
      length: 3,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final hasCover = game.cover != null && game.cover!.isNotEmpty;
          final heroHeight = hasCover
              ? min(constraints.maxHeight * 0.4, 340.0)
              : 120.0;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                key: const ValueKey('detail-hero'),
                height: heroHeight,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (hasCover)
                      Container(
                        color: colorScheme.surfaceContainerHigh,
                        foregroundDecoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              colorScheme.surfaceContainerLow,
                            ],
                            stops: const [0.55, 1.0],
                          ),
                        ),
                        child: _heroArt(
                            context, ref, constraints.maxWidth),
                      )
                    else
                      Container(color: colorScheme.surfaceContainerHigh),
                    Positioned(
                      top: 16,
                      left: 16,
                      right: 148,
                      child: Text(
                        game.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              shadows: const [
                                Shadow(
                                  blurRadius: 8,
                                  color: Colors.black87,
                                ),
                              ],
                            ),
                      ),
                    ),
                    Positioned(
                      top: 12,
                      right: 12,
                      child: _HeroControls(game: game),
                    ),
                  ],
                ),
              ),
              TabBar(
                isScrollable: false,
                tabAlignment: TabAlignment.fill,
                indicatorColor: colorScheme.primary,
                labelColor: colorScheme.primary,
                unselectedLabelColor: colorScheme.onSurfaceVariant,
                tabs: const [
                  Tab(text: 'Info'),
                  Tab(text: 'Launch'),
                  Tab(text: 'History'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    InfoTab(game: game),
                    LaunchTab(game: game),
                    HistoryTab(game: game),
                  ],
                ),
              ),
              _Footer(game: game),
            ],
          );
        },
      ),
    );
  }

  Widget _heroArt(
      BuildContext context, WidgetRef ref, double width) {
    final dir = ref.watch(dataDirProvider);
    final exists = ref.watch(coverExistsProvider);
    final thumb = thumbPath(dir, game.id, 512);
    final physicalWidth =
        (width * MediaQuery.devicePixelRatioOf(context)).round().clamp(
      1,
      1 << 16,
    );
    final original = File(p.join(dir.coversOriginal.path, game.cover!));
    return Stack(
      fit: StackFit.expand,
      children: [
        if (exists(thumb))
          Image.file(
            File(thumb),
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        Image.file(
          original,
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          gaplessPlayback: true,
          cacheWidth: physicalWidth,
          frameBuilder: (context, child, frame, _) =>
              frame == null ? const SizedBox.shrink() : child,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      ],
    );
  }
}

ButtonStyle _heroButtonStyle() => IconButton.styleFrom(
      backgroundColor: Colors.black45,
      foregroundColor: Colors.white,
      minimumSize: const Size(36, 36),
      padding: EdgeInsets.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );

class _HeroControls extends ConsumerWidget {
  const _HeroControls({required this.game});

  final Game game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [
        IconButton(
          tooltip: game.favourite ? 'Unfavourite' : 'Favourite',
          icon: Icon(game.favourite
              ? Icons.star_rounded
              : Icons.star_outline_rounded),
          style: _heroButtonStyle(),
          onPressed: () => ref.read(gameEditorProvider).update(
              game.id, (g) => g.favourite = !g.favourite,
              context: context),
        ),
        PopupMenuButton<String>(
          tooltip: 'More',
          icon: const Icon(Icons.more_vert_rounded),
          style: _heroButtonStyle(),
          onSelected: (value) {
            switch (value) {
              case 'cover':
                _changeCover(context, ref, game);
              case 'refetch':
                _refetchCover(context, ref, game);
              case 'delete':
                _deleteGame(context, ref, game);
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'cover',
              child: Text('Change cover…'),
            ),
            if (game.vndbId != null)
              const PopupMenuItem(
                value: 'refetch',
                child: Text('Re-fetch cover from VNDB'),
              ),
            const PopupMenuItem(
              value: 'delete',
              child: Text('Delete game…'),
            ),
          ],
        ),
        IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close_rounded),
          style: _heroButtonStyle(),
          onPressed: () =>
              ref.read(selectedGameIdProvider.notifier).clear(),
        ),
      ],
    );
  }
}

Future<void> _storeCoverBytes(
    BuildContext context, WidgetRef ref, Game game, List<int> bytes) async {
  final dir = ref.read(dataDirProvider);
  final name =
      await storeOriginal(dir, game.id, Uint8List.fromList(bytes));
  if (!context.mounted) return;
  await ref
      .read(gameEditorProvider)
      .update(game.id, (g) => g.cover = name, context: context);
  await generateThumbnails(dir, [(game.id, name)]);
  ref.invalidate(coverExistsProvider);
  for (final width in thumbWidths) {
    await FileImage(File(thumbPath(dir, game.id, width))).evict();
  }
  await FileImage(File(p.join(dir.coversOriginal.path, name))).evict();
}

Future<void> _changeCover(
    BuildContext context, WidgetRef ref, Game game) async {
  final picked = await ref.read(coverPickerProvider)();
  if (picked == null || picked.isEmpty) return;
  if (!context.mounted) return;
  if (picked.startsWith('/run/user/')) {
    Toast(context).show('That file came through the Flatpak portal. '
        'Pick it from its real location.');
    return;
  }
  try {
    final bytes = await File(picked).readAsBytes();
    if (!context.mounted) return;
    await _storeCoverBytes(context, ref, game, bytes);
  } catch (e) {
    if (context.mounted) Toast(context).showError('Could not use cover: $e');
  }
}

Future<void> _refetchCover(
    BuildContext context, WidgetRef ref, Game game) async {
  final vndbId = game.vndbId;
  if (vndbId == null) return;
  try {
    final url = await VndbClient().fetchCoverUrl(vndbId);
    if (url == null) {
      if (context.mounted) {
        Toast(context).showError('VNDB has no cover for this game.');
      }
      return;
    }
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw VndbException('HTTP ${response.statusCode}');
    }
    if (!context.mounted) return;
    await _storeCoverBytes(context, ref, game, response.bodyBytes);
  } catch (e) {
    if (context.mounted) {
      Toast(context).showError('Cover re-fetch failed: $e');
    }
  }
}

Future<void> _deleteGame(
    BuildContext context, WidgetRef ref, Game game) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Delete ${game.title}?'),
      content: const Text("It moves to the trash folder in vnl's data "
          'folder and can be restored by hand.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(dialogContext).colorScheme.error,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) {
    return;
  }
  await moveToTrash(ref.read(dataDirProvider), game);
  if (!context.mounted) return;
  await ref.read(gameEditorProvider).remove(game.id, context: context);
}

class _Footer extends ConsumerWidget {
  const _Footer({required this.game});

  final Game game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = ref.watch(launchActionsProvider);
    final LaunchMode mode = game.launch.mode ?? ref.watch(launchModeProvider);
    final phase = ref.watch(runningGamesProvider)[game.id];
    final busy = phase != null;
    final showRunExe =
        mode == LaunchMode.proton || mode == LaunchMode.wine;
    final launchTip = _launchTooltip(ref, phase, mode);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          if (showRunExe)
            Tooltip(
              message: _phaseLabel(phase),
              child: SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => actions.runExeInPrefix(context, game),
                  child: const Text('Run .exe inside prefix'),
                ),
              ),
            ),
          Tooltip(
            message: launchTip ?? '',
            child: SizedBox(
              width: double.infinity,
              height: 44,
              child: FilledButton(
                onPressed: launchTip == null
                    ? () => actions.launch(context, game)
                    : null,
                child: switch (phase) {
                  LaunchPhase.starting => const Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 8,
                      children: [
                        SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        Text('Launching…'),
                      ],
                    ),
                  LaunchPhase.running => const Text('Running'),
                  // `ended` entries are removed, so this is unreachable.
                  LaunchPhase.ended || null => const Text('Launch'),
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _phaseLabel(LaunchPhase? phase) => switch (phase) {
        LaunchPhase.starting => 'Launching…',
        LaunchPhase.running => 'Running',
        // `ended` entries are removed, so this is unreachable.
        LaunchPhase.ended || null => '',
      };

  String? _launchTooltip(
      WidgetRef ref, LaunchPhase? phase, LaunchMode mode) {
    if (phase != null) return _phaseLabel(phase);
    if (mode == LaunchMode.steam) {
      if (game.launch.steamAppId == null) return 'Steam App ID is not set';
    } else {
      final exe = game.launch.executable;
      if (exe == null || exe.isEmpty) return 'No executable set';
      if (mode == LaunchMode.proton &&
          ref.watch(umuRunPathProvider) == null) {
        return 'umu-run not found on PATH';
      }
    }
    return null;
  }
}
