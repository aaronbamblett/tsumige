// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../../core/covers.dart';
import '../../../../core/model.dart';
import '../../../../utils/prefs/app_prefs.dart' hide LaunchMode;
import '../../data/library_repository.dart';
import '../../domain/cover_source.dart';
import '../../domain/launch_actions.dart';
import '../../domain/running_games.dart';
import '../../domain/selection.dart';
import 'detail_tabs/history_tab.dart';
import 'detail_tabs/info_tab.dart';
import 'detail_tabs/launch_tab.dart';
import 'detail_tabs/routes_tab.dart';



class GameDetailPane extends ConsumerWidget {
  const GameDetailPane({super.key, required this.game});

  final Game game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    return DefaultTabController(
      length: 4,
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
                      right: 68,
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
                      child: IconButton(
                        tooltip: 'Close',
                        icon: const Icon(Icons.close_rounded),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black45,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(36, 36),
                          padding: EdgeInsets.zero,
                          tapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () => ref
                            .read(selectedGameIdProvider.notifier)
                            .clear(),
                      ),
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
                  Tab(text: 'Routes'),
                  Tab(text: 'History'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    InfoTab(game: game),
                    LaunchTab(game: game),
                    RoutesTab(game: game),
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

class _Footer extends ConsumerWidget {
  const _Footer({required this.game});

  final Game game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = ref.watch(launchActionsProvider);
    final LaunchMode mode = game.launch.mode ?? ref.watch(launchModeProvider);
    final running = ref.watch(runningGamesProvider).contains(game.id);
    final showRunExe =
        mode == LaunchMode.proton || mode == LaunchMode.wine;
    final launchTip = _launchTooltip(ref, running, mode);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          if (showRunExe)
            Tooltip(
              message: running ? 'Running' : '',
              child: SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton(
                  onPressed: running
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
                child: Text(running ? 'Running' : 'Launch'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String? _launchTooltip(WidgetRef ref, bool running, LaunchMode mode) {
    if (running) return 'Running';
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
