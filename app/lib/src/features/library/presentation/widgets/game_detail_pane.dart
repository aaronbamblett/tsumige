// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../../core/covers.dart';
import '../../../../core/groups.dart';
import '../../../../core/launch/game_runner.dart';
import '../../../../core/launch/launch_modes.dart';
import '../../../../core/model.dart';
import '../../../../core/trash.dart';
import '../../../../utils/platform/platform_runtime.dart';
import '../../../../utils/theme/brand.dart';
import '../../data/library_repository.dart';
import '../../domain/cover_source.dart';
import '../../domain/game_editor.dart';
import '../../domain/launch_actions.dart';
import '../../domain/running_games.dart';
import '../../domain/selection.dart';
import 'art_image.dart';
import 'art_overlay.dart';
import 'art_picker_dialog.dart';
import 'detail_tabs/history_tab.dart';
import 'detail_tabs/info_tab.dart';
import 'detail_tabs/launch_tab.dart';
import 'detail_tabs/related_tab.dart';
import 'edit_details_dialog.dart';

/// Pane hero height; the art covers the full width from the top.
const double _kHeroHeight = 340;

/// Room the hero gives up when the pane is short: tabs (61), the footer
/// (139) and a 120 px tab body. Below 340 px of spare height the hero shrinks.
const double _kHeroReserve = 61 + 139 + 120;

class GameDetailPane extends HookConsumerWidget {
  const GameDetailPane({super.key, required this.game, this.group});

  final Game game;

  /// When the selected tile is a group, [game] is its picked member.
  final GameGroup? group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final infoScroll = useScrollController();
    final launchScroll = useScrollController();
    final historyScroll = useScrollController();
    final relatedScroll = useScrollController();
    final hasCover = game.cover != null && game.cover!.isNotEmpty;
    final hasBackground = game.background?.isNotEmpty ?? false;
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
                    if (hasCover || hasBackground)
                      _heroArt(context, ref, constraints.maxWidth),
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
                      child: _HeroControls(game: game, group: group),
                    ),
                    Positioned(
                      left: 20,
                      right: 20,
                      bottom: 16,
                      child: _HeroTitle(game: game, group: group),
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
    final version = ref.watch(artVersionProvider);
    final physicalWidth = (width * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(1, 1 << 16);
    final background = game.background;
    if (background != null && background.isNotEmpty) {
      final file = File(p.join(dir.coversBackground.path, background));
      if (exists(file.path)) {
        return Image(
          image: artFileImage(
            file,
            version: version(file.path),
            cacheWidth: physicalWidth,
          ),
          fit: BoxFit.cover,
          alignment: game.backgroundAlignment ?? kDetailPaneArtAlignment,
          gaplessPlayback: true,
          frameBuilder: (context, child, frame, _) =>
              frame == null ? const SizedBox.shrink() : child,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        );
      }
    }
    if (game.cover == null || game.cover!.isEmpty) return const SizedBox.shrink();
    final thumb = thumbPath(dir, game.id, 512);
    final original = File(p.join(dir.coversOriginal.path, game.cover!));
    final alignment = game.backgroundAlignment ?? kDetailPaneArtAlignment;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (exists(thumb))
          Image(
            image: artFileImage(File(thumb), version: version(thumb)),
            fit: BoxFit.cover,
            alignment: alignment,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        Image(
          image: artFileImage(
            original,
            version: version(original.path),
            cacheWidth: physicalWidth,
          ),
          fit: BoxFit.cover,
          alignment: alignment,
          gaplessPlayback: true,
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

class _HeroTitle extends ConsumerWidget {
  const _HeroTitle({required this.game, required this.group});

  final Game game;
  final GameGroup? group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
            fontWeight: FontWeight.w600,
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
        if (group != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _EpisodePicker(game: game, group: group!),
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

/// Compact episode picker under the hero title for a grouped game: the
/// stacked-pages icon, the member's short name, `· N of M`, and a `▾`.
/// The menu lists every member by short name, with a check on the current
/// one and a muted `Played` note for members with any play session.
class _EpisodePicker extends ConsumerWidget {
  const _EpisodePicker({required this.game, required this.group});

  final Game game;
  final GameGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final games = ref.watch(libraryProvider).value?.library.games ?? const [];
    final byId = {for (final g in games) g.id: g};
    final members = [
      for (final id in group.memberIds)
        if (byId[id] != null) byId[id]!,
    ];
    if (members.isEmpty) return const SizedBox.shrink();
    final index = members.indexWhere((m) => m.id == game.id);
    final short = memberShortName(group, game, byId);
    return PopupMenuButton<String>(
      tooltip: 'Choose episode',
      padding: EdgeInsets.zero,
      onSelected: (memberId) => ref
          .read(gameEditorProvider)
          .pickGroupMember(group.id, memberId, context: context),
      itemBuilder: (context) => [
        for (final m in members)
          PopupMenuItem(
            value: m.id,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 8,
              children: [
                SizedBox(
                  width: 20,
                  child: m.id == game.id
                      ? const Icon(Icons.check_rounded, size: 18)
                      : null,
                ),
                Flexible(child: Text(memberShortName(group, m, byId))),
                if (m.playSessions.isNotEmpty)
                  Text(
                    'Played',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(11),
          color: ArtOverlay.button,
          border: Border.all(color: ArtOverlay.badgeRing),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [
            const Icon(
              Icons.collections_bookmark_outlined,
              size: 16,
              color: OnImage.text,
            ),
            Flexible(
              child: Text(
                '$short · ${index >= 0 ? index + 1 : 1} of ${members.length}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: OnImage.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Icon(
              Icons.arrow_drop_down_rounded,
              size: 18,
              color: OnImage.text,
            ),
          ],
        ),
      ),
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
  const _HeroControls({required this.game, required this.group});

  final Game game;
  final GameGroup? group;

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
              case 'edit':
                showEditDetailsDialog(context, game);
              case 'art':
                showArtPickerDialog(context, game);
              case 'adult':
                ref
                    .read(gameEditorProvider)
                    .update(
                      game.id,
                      (g) => g.adultOverride = !g.isAdult,
                      context: context,
                    );
              case 'adult-vndb':
                ref
                    .read(gameEditorProvider)
                    .update(
                      game.id,
                      (g) => g.adultOverride = null,
                      context: context,
                    );
              case 'delete':
                _deleteGame(context, ref, game);
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'edit', child: Text('Edit…')),
            const PopupMenuItem(value: 'art', child: Text('Change art…')),
            PopupMenuItem(
              value: 'adult',
              child: Text(game.isAdult ? 'Mark as not adult' : 'Mark as adult'),
            ),
            if (game.adultOverride != null)
              const PopupMenuItem(
                value: 'adult-vndb',
                child: Text("Use VNDB's adult flag"),
              ),
            const PopupMenuItem(
              value: 'delete',
              child: Text('Remove from library…'),
            ),
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

Future<void> _deleteGame(BuildContext context, WidgetRef ref, Game game) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Remove ${game.title}?'),
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
          child: const Text('Remove'),
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
    final platform = ref.watch(hostPlatformProvider);
    final LaunchMode mode = effectiveLaunchMode(game, platform);
    final phase = ref.watch(runningGamesProvider)[game.id];
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
    final unavailable =
        launchModeUnavailableMessage(mode, ref.watch(hostPlatformProvider));
    if (unavailable != null) return unavailable;
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
