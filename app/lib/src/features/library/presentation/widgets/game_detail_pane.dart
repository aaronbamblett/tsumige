// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;

import 'package:http/http.dart' as http;

import '../../../../core/covers.dart';
import '../../../../core/launch/game_runner.dart';
import '../../../../core/model.dart';
import '../../../../core/trash.dart';
import '../../../../core/vndb.dart';
import '../../../../utils/prefs/app_prefs.dart' hide LaunchMode;
import '../../../../utils/theme/brand.dart';
import '../../../../utils/toast.dart';
import '../../data/library_repository.dart';
import '../../domain/cover_source.dart';
import '../../domain/game_editor.dart';
import '../../domain/launch_actions.dart';
import '../../domain/running_games.dart';
import '../../domain/selection.dart';
import 'art_overlay.dart';
import 'detail_tabs/history_tab.dart';
import 'detail_tabs/info_tab.dart';
import 'detail_tabs/launch_tab.dart';
import 'detail_tabs/related_tab.dart';

/// Pane hero height; the art covers the full width from the top.
const double _kHeroHeight = 340;

/// Room the hero gives up when the pane is short: tabs (61), the footer
/// (139) and a 120 px tab body. Below 340 px of spare height the hero shrinks.
const double _kHeroReserve = 61 + 139 + 120;

class GameDetailPane extends HookConsumerWidget {
  const GameDetailPane({super.key, required this.game});

  final Game game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final infoScroll = useScrollController();
    final launchScroll = useScrollController();
    final historyScroll = useScrollController();
    final relatedScroll = useScrollController();
    final hasCover = game.cover != null && game.cover!.isNotEmpty;
    return DefaultTabController(
      length: 4,
      child: LayoutBuilder(
        builder: (context, paneConstraints) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              key: const ValueKey('detail-hero'),
              height: min(
                _kHeroHeight,
                max(0, paneConstraints.maxHeight - _kHeroReserve),
              ),
              width: double.infinity,
              child: LayoutBuilder(
                builder: (context, constraints) => Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(color: colorScheme.surfaceContainerHigh),
                    if (hasCover) _heroArt(context, ref, constraints.maxWidth),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            colorScheme.surfaceContainer.withValues(alpha: 0),
                            colorScheme.surfaceContainer.withValues(
                              alpha: 0.55,
                            ),
                            colorScheme.surfaceContainer,
                          ],
                          stops: const [0.35, 0.62, 1.0],
                        ),
                      ),
                    ),
                    const Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: 70,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [ArtOverlay.scrimTop, Colors.transparent],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 12,
                      right: 12,
                      child: _HeroControls(game: game),
                    ),
                    Positioned(
                      left: 20,
                      right: 20,
                      bottom: 16,
                      child: _HeroTitle(game: game),
                    ),
                  ],
                ),
              ),
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                final tabWidth = (constraints.maxWidth - 24) / 4;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: TabBar(
                    tabAlignment: TabAlignment.fill,
                    dividerColor: colorScheme.outlineVariant,
                    indicatorSize: TabBarIndicatorSize.tab,
                    indicator: UnderlineTabIndicator(
                      borderSide: BorderSide(
                        color: colorScheme.primary,
                        width: 2,
                      ),
                      insets: EdgeInsets.symmetric(horizontal: tabWidth * 0.22),
                    ),
                    overlayColor: const WidgetStatePropertyAll(
                      Color(0x08FFFFFF),
                    ),
                    labelColor: colorScheme.primary,
                    unselectedLabelColor: colorScheme.onSurfaceVariant,
                    labelStyle: const TextStyle(fontSize: 12.5),
                    unselectedLabelStyle: const TextStyle(fontSize: 12.5),
                    tabs: const [
                      Tab(
                        height: 60,
                        iconMargin: EdgeInsets.only(bottom: 4),
                        icon: Icon(Icons.info_outline_rounded, size: 20),
                        text: 'Info',
                      ),
                      Tab(
                        height: 60,
                        iconMargin: EdgeInsets.only(bottom: 4),
                        icon: Icon(Icons.settings_rounded, size: 20),
                        text: 'Launch',
                      ),
                      Tab(
                        height: 60,
                        iconMargin: EdgeInsets.only(bottom: 4),
                        icon: Icon(Icons.history_rounded, size: 20),
                        text: 'History',
                      ),
                      Tab(
                        height: 60,
                        iconMargin: EdgeInsets.only(bottom: 4),
                        icon: Icon(Icons.link_rounded, size: 20),
                        text: 'Related',
                      ),
                    ],
                  ),
                );
              },
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _TabBody(
                    controller: infoScroll,
                    child: InfoTab(game: game),
                  ),
                  _TabBody(
                    controller: launchScroll,
                    child: LaunchTab(game: game),
                  ),
                  _TabBody(
                    controller: historyScroll,
                    child: HistoryTab(game: game),
                  ),
                  _TabBody(
                    controller: relatedScroll,
                    child: RelatedTab(game: game),
                  ),
                ],
              ),
            ),
            _Footer(game: game),
          ],
        ),
      ),
    );
  }

  Widget _heroArt(BuildContext context, WidgetRef ref, double width) {
    final dir = ref.watch(dataDirProvider);
    final exists = ref.watch(coverExistsProvider);
    final thumb = thumbPath(dir, game.id, 512);
    final physicalWidth = (width * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(1, 1 << 16);
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

/// Each tab body owns its scroll controller, so the scrollbar and the tab's
/// scroll view never share the primary controller with another tab.
class _TabBody extends StatelessWidget {
  const _TabBody({required this.controller, required this.child});

  final ScrollController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PrimaryScrollController(
      controller: controller,
      child: Scrollbar(
        controller: controller,
        thumbVisibility: true,
        child: child,
      ),
    );
  }
}

class _HeroTitle extends StatelessWidget {
  const _HeroTitle({required this.game});

  final Game game;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final original = game.vndbOriginalTitle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          game.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: OnImage.text,
            fontSize: 30,
            fontWeight: FontWeight.w700,
            height: 1.15,
            shadows: [
              Shadow(
                offset: const Offset(0, 2),
                blurRadius: 10,
                color: OnImage.shadow.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
        if (original != null && original.isNotEmpty && original != game.title)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              original,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 15,
                shadows: [
                  Shadow(
                    offset: const Offset(0, 1),
                    blurRadius: 6,
                    color: OnImage.shadow.withValues(alpha: 0.7),
                  ),
                ],
              ),
            ),
          ),
        if (game.vndbRating != null ||
            (game.released?.isNotEmpty ?? false))
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: _MetaRow(game: game),
          ),
      ],
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.game});

  final Game game;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final style = TextStyle(
      color: colorScheme.onSurfaceVariant,
      fontSize: 13.5,
    );
    final votes = game.vndbVotecount;
    final rating = game.vndbRating;
    final released = game.released;
    final hasRelease = released != null && released.isNotEmpty;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 10,
      children: [
        if (rating != null) ...[
          Text(
            '★ ${(rating / 10).toStringAsFixed(1)}',
            style: TextStyle(color: colorScheme.primary, fontSize: 13.5),
          ),
          Flexible(
            child: Text(
              votes == null ? 'VNDB Rating' : 'VNDB Rating · $votes votes',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        ],
        if (rating != null && hasRelease)
          Container(
            width: 1,
            height: 14,
            color: OnImage.text.withValues(alpha: 0.25),
          ),
        if (hasRelease)
          Text(
            released,
            style: TextStyle(color: colorScheme.onSurface, fontSize: 13.5),
          ),
      ],
    );
  }
}

class _HeroButton extends StatefulWidget {
  const _HeroButton({required this.icon, this.tooltip, this.onPressed});

  final IconData icon;
  final String? tooltip;
  final VoidCallback? onPressed;

  @override
  State<_HeroButton> createState() => _HeroButtonState();
}

class _HeroButtonState extends State<_HeroButton> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final button = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _hovered ? ArtOverlay.buttonHover : ArtOverlay.button,
            border: Border.all(
              color: _hovered
                  ? ArtOverlay.buttonRingHover
                  : ArtOverlay.buttonRing,
            ),
            boxShadow: ArtOverlay.buttonShadow,
          ),
          child: Icon(widget.icon, size: 20, color: OnImage.text),
        ),
      ),
    );
    final tooltip = widget.tooltip;
    if (tooltip == null) return button;
    return Tooltip(message: tooltip, child: button);
  }
}

class _HeroControls extends ConsumerWidget {
  const _HeroControls({required this.game});

  final Game game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [
        _HeroButton(
          tooltip: game.favourite ? 'Unfavourite' : 'Favourite',
          icon: game.favourite
              ? Icons.favorite_rounded
              : Icons.favorite_border_rounded,
          onPressed: () => ref
              .read(gameEditorProvider)
              .update(
                game.id,
                (g) => g.favourite = !g.favourite,
                context: context,
              ),
        ),
        PopupMenuButton<String>(
          tooltip: 'More',
          padding: EdgeInsets.zero,
          splashRadius: 19,
          child: const _HeroButton(icon: Icons.more_vert_rounded),
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
            const PopupMenuItem(value: 'cover', child: Text('Change cover…')),
            if (game.vndbId != null)
              const PopupMenuItem(
                value: 'refetch',
                child: Text('Re-fetch cover from VNDB'),
              ),
            const PopupMenuItem(value: 'delete', child: Text('Delete game…')),
          ],
        ),
        _HeroButton(
          tooltip: 'Close',
          icon: Icons.close_rounded,
          onPressed: () => ref.read(selectedGameIdProvider.notifier).clear(),
        ),
      ],
    );
  }
}

Future<void> _storeCoverBytes(
  BuildContext context,
  WidgetRef ref,
  Game game,
  List<int> bytes,
) async {
  final dir = ref.read(dataDirProvider);
  final name = await storeOriginal(dir, game.id, Uint8List.fromList(bytes));
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
  BuildContext context,
  WidgetRef ref,
  Game game,
) async {
  final picked = await ref.read(coverPickerProvider)();
  if (picked == null || picked.isEmpty) return;
  if (!context.mounted) return;
  if (picked.startsWith('/run/user/')) {
    Toast(context).show(
      'That file came through the Flatpak portal. '
      'Pick it from its real location.',
    );
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
  BuildContext context,
  WidgetRef ref,
  Game game,
) async {
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

Future<void> _deleteGame(BuildContext context, WidgetRef ref, Game game) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Delete ${game.title}?'),
      content: const Text(
        "It moves to the trash folder in vnl's data "
        'folder and can be restored by hand.',
      ),
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
    final scheme = Theme.of(context).colorScheme;
    final LaunchMode mode = game.launch.mode ?? ref.watch(launchModeProvider);
    final phase = ref.watch(runningGamesProvider)[game.id];
    final busy = phase != null;
    final showRunExe = mode == LaunchMode.proton || mode == LaunchMode.wine;
    final launchTip = _launchTooltip(ref, phase, mode);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          if (showRunExe)
            Tooltip(
              message: _phaseLabel(phase),
              child: BrandGlassButton(
                height: 44,
                onPressed: busy
                    ? null
                    : () => actions.runExeInPrefix(context, game),
                icon: const Icon(Icons.terminal_rounded),
                label: const Text('Run .exe inside prefix…'),
              ),
            ),
          Tooltip(
            message: launchTip ?? '',
            child: BrandButton(
              height: 52,
              onPressed: launchTip == null
                  ? () => actions.launch(context, game)
                  : null,
              icon: switch (phase) {
                LaunchPhase.starting => SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: BrandColors.of(context).onGradient,
                  ),
                ),
                LaunchPhase.running => null,
                // `ended` entries are removed, so this is unreachable.
                LaunchPhase.ended || null => const Icon(
                  Icons.play_arrow_rounded,
                  size: 22,
                ),
              },
              label: Text(switch (phase) {
                LaunchPhase.starting => 'Launching…',
                LaunchPhase.running => 'Running',
                LaunchPhase.ended || null => 'Play',
              }),
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

  String? _launchTooltip(WidgetRef ref, LaunchPhase? phase, LaunchMode mode) {
    if (phase != null) return _phaseLabel(phase);
    if (mode == LaunchMode.steam) {
      if (game.launch.steamAppId == null) return 'Steam App ID is not set';
    } else {
      final exe = game.launch.executable;
      if (exe == null || exe.isEmpty) return 'No executable set';
      if (mode == LaunchMode.proton && ref.watch(umuRunPathProvider) == null) {
        return 'umu-run not found on PATH';
      }
    }
    return null;
  }
}
