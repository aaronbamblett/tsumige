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

import '../../../core/launch/session_recorder.dart';
import '../../../core/model.dart' as core;
import '../../../utils/prefs/app_prefs.dart';
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
              'startup_ms=${DateTime.now().difference(entry).inMilliseconds}');
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
    final total =
        libraryAsync.value?.library.games.length ?? games.length;
    final selected = ref.watch(selectedGameProvider);
    final defaultMode = ref.watch(launchModeProvider);
    final umuMissing = ref.watch(umuRunPathProvider) == null;
    final libraryGames = libraryAsync.value?.library.games ?? const [];
    final usesProton = defaultMode == core.LaunchMode.proton ||
        libraryGames.any(
            (game) => (game.launch.mode ?? defaultMode) == core.LaunchMode.proton);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            LibraryToolbar(shown: games.length, total: total),
            SkippedBanner(
              skipped:
                  libraryAsync.value?.skipped ?? const [],
            ),
            if (umuMissing && usesProton) const _UmuBanner(),
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
                          width: 400,
                          margin: const EdgeInsets.only(
                              top: 12, right: 12, bottom: 12),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerLow,
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
        ),
      ),
    );
  }
}
