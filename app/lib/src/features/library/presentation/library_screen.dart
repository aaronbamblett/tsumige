// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/launch/launch_modes.dart';
import '../../../core/launch/session_recorder.dart';
import '../../../core/model.dart' as core;
import '../../../utils/platform/platform_runtime.dart';
import '../../../utils/startup_time.dart';
import '../../../utils/toast.dart';
import '../data/library_repository.dart';
import '../domain/cover_source.dart';
import '../domain/launch_actions.dart';
import '../domain/selection.dart';
import 'widgets/game_detail_pane.dart';
import 'widgets/library_grid.dart';
import 'widgets/library_toolbar.dart';
import 'widgets/skipped_banner.dart';

/// One-line banner shown when Proton games cannot launch because `umu-run`
/// is missing from PATH. It sits next to the skipped-entries banner.
class _UmuBanner extends StatelessWidget {
  const _UmuBanner();

  @override
  Widget build(BuildContext context) {
    return const Card(
      margin: EdgeInsets.all(8),
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Text(
          "umu-run was not found on PATH, so Proton games can't launch.",
        ),
      ),
    );
  }
}

const double _kPaneWidth = 440;
const double _kPaneMargin = 12;
const double _kPaneSlotWidth = _kPaneWidth + 2 * _kPaneMargin;

/// The library view: toolbar above a lazy cover grid. After the first frame
/// with data it prints `startup_ms` and fills in missing thumbnails in the
/// background, rebuilding tiles only when thumbnails were generated.
class LibraryScreen extends HookConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final libraryAsync = ref.watch(libraryProvider);
    final games = ref.watch(visibleGamesProvider);
    final kicked = useState(false);
    useEffect(() {
      if (kicked.value || !libraryAsync.hasValue) return null;
      kicked.value = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final entry = appMainEntry;
        if (entry != null && !startupReported) {
          startupReported = true;
          stderr.writeln(
            'startup_ms=${DateTime.now().difference(entry).inMilliseconds}',
          );
        }
        final recovered = await recoverSessions(
          ref.read(dataDirProvider),
          ref.read(sessionStoreProvider),
        );
        if (recovered > 0) {
          ref.invalidate(libraryProvider);
          if (context.mounted) {
            Toast(context).show('Recovered $recovered play session(s)');
          }
        }
        final loaded = ref.read(libraryProvider).value;
        if (loaded == null) return;
        final report = await ref
            .read(libraryRepositoryProvider)
            .ensureThumbnails(loaded.library);
        if (report.generated > 0) {
          ref.invalidate(coverExistsProvider);
        }
      });
      return null;
    }, [libraryAsync.hasValue]);
    final selected = ref.watch(selectedGameProvider);
    final platform = ref.watch(hostPlatformProvider);
    final onLinux = platform.isLinux;
    final umuMissing = ref.watch(umuRunPathProvider) == null;
    final libraryGames = libraryAsync.value?.library.games ?? const [];
    final usesProton = libraryGames.any(
      (game) =>
          effectiveLaunchMode(game, platform) == core.LaunchMode.proton,
    );
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final gridWidth =
                constraints.maxWidth - (selected == null ? 0 : _kPaneSlotWidth);
            return Column(
              children: [
                LibraryToolbar(
                  gridRight: gridWidth - LibraryGrid.horizontalPadding,
                ),
                SkippedBanner(skipped: libraryAsync.value?.skipped ?? const []),
                if (onLinux && umuMissing && usesProton) const _UmuBanner(),
                Expanded(
                  child: Focus(
                    autofocus: true,
                    onKeyEvent: (node, event) {
                      if (event is KeyDownEvent &&
                          event.logicalKey == LogicalKeyboardKey.escape) {
                        ref.read(selectedGameIdProvider.notifier).clear();
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: LibraryGrid(games: games)),
                        if (selected != null)
                          Container(
                            width: _kPaneWidth,
                            margin: const EdgeInsets.all(_kPaneMargin),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainer,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outlineVariant,
                                width: 1,
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: GameDetailPane(
                              key: ValueKey(selected.id),
                              game: selected,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
