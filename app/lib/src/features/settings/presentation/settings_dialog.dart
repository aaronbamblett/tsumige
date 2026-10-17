// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../utils/extensions/l10n.dart';
import 'sections/about_section.dart';
import 'sections/advanced_section.dart';
import 'sections/appearance_section.dart';
import 'sections/launching_section.dart';
import 'sections/library_section.dart';

export 'sections/settings_widgets.dart'
    show folderOpenerProvider, pickFolderOrNull;

enum SettingsSection {
  appearance('Appearance', Icons.palette_outlined),
  library('Library', Icons.folder_outlined),
  launching('Launching', Icons.rocket_launch_outlined),
  advanced('Advanced', Icons.build_rounded),
  about('About', Icons.info_outline_rounded);

  const SettingsSection(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Opens the settings popup over the current screen.
Future<void> showSettingsDialog(BuildContext context) {
  final window = MediaQuery.sizeOf(context);
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (context) => SettingsDialog(
      size: Size(
        math.min(960.0, window.width * 0.9),
        math.min(720.0, window.height * 0.9),
      ),
    ),
  );
}

class SettingsDialog extends ConsumerStatefulWidget {
  const SettingsDialog({super.key, required this.size});

  final Size size;

  /// The section most recently opened, kept for the session.
  static SettingsSection lastSection = SettingsSection.appearance;

  @override
  ConsumerState<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends ConsumerState<SettingsDialog> {
  late SettingsSection _section = SettingsDialog.lastSection;
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _select(SettingsSection section) {
    if (_section == section) return;
    setState(() => _section = section);
    SettingsDialog.lastSection = section;
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  void _close() => Navigator.of(context).pop();

  Widget _content() => switch (_section) {
    SettingsSection.appearance => const AppearanceSection(),
    SettingsSection.library => const LibrarySection(),
    SettingsSection.launching => const LaunchingSection(),
    SettingsSection.advanced => const AdvancedSection(),
    SettingsSection.about => const AboutSection(),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Dialog(
      insetPadding: EdgeInsets.zero,
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        key: const Key('settings-dialog'),
        width: widget.size.width,
        height: widget.size.height,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.escape) {
              _close();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 12, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.l10n.settings,
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      key: const Key('settings-close'),
                      tooltip: 'Close',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: _close,
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: scheme.outlineVariant),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 220,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            for (final section in SettingsSection.values)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: _NavItem(
                                  section: section,
                                  selected: _section == section,
                                  onTap: () => _select(section),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: Scrollbar(
                        controller: _scrollController,
                        thumbVisibility: true,
                        thickness: 8,
                        radius: const Radius.circular(4),
                        child: SingleChildScrollView(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(24),
                          child: _content(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.section,
    required this.selected,
    required this.onTap,
  });

  final SettingsSection section;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      child: SizedBox(
        height: 44,
        child: Material(
          color: selected ? scheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: Key('settings-nav-${section.name}'),
            onTap: onTap,
            hoverColor: scheme.onSurface.withValues(alpha: 0.06),
            child: Row(
              children: [
                Container(
                  key: selected
                      ? Key('settings-nav-selected-${section.name}')
                      : null,
                  width: 3,
                  height: double.infinity,
                  color: selected ? scheme.primary : Colors.transparent,
                ),
                const SizedBox(width: 12),
                Icon(
                  section.icon,
                  size: 20,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    section.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: selected ? scheme.primary : scheme.onSurface,
                      fontWeight: selected ? FontWeight.w600 : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
