// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../core/model.dart';
import '../../../domain/game_editor.dart';
import '../../../domain/vndb_markup.dart';

TextStyle? detailSectionLabelStyle(BuildContext context) {
  final theme = Theme.of(context);
  return theme.textTheme.labelSmall?.copyWith(
    color: theme.colorScheme.onSurfaceVariant,
    letterSpacing: 1.0,
  );
}

Widget detailSectionDivider(BuildContext context) => Divider(
      height: 24,
      thickness: 1,
      color: Theme.of(context).colorScheme.outlineVariant,
    );

class DetailSection extends StatelessWidget {
  const DetailSection(
      {super.key, required this.label, required this.child, this.actions = const []});

  final String label;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(label, style: detailSectionLabelStyle(context)),
            const Spacer(),
            ...actions,
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class InfoTab extends ConsumerWidget {
  const InfoTab({super.key, required this.game});

  final Game game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final labelStyle = detailSectionLabelStyle(context);
    final blocks = <Widget>[];
    if (game.vndbRating != null ||
        (game.released != null && game.released!.isNotEmpty)) {
      blocks.add(_facts(theme, labelStyle));
    }
    if (game.tags.isNotEmpty) {
      blocks.add(_TagsSection(game: game));
    }
    blocks.add(_MarkupSection(
      game: game,
      label: 'DESCRIPTION',
      emptyHint: 'No description',
      editTooltip: 'Edit description',
      getValue: (g) => g.description,
      setValue: (g, v) => g.description = v,
    ));
    blocks.add(_MarkupSection(
      game: game,
      label: 'NOTES',
      emptyHint: 'No notes',
      editTooltip: 'Edit notes',
      getValue: (g) => g.notes,
      setValue: (g, v) => g.notes = v,
    ));
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < blocks.length; i++) ...[
            if (i > 0) detailSectionDivider(context),
            blocks[i],
          ],
        ],
      ),
    );
  }

  Widget _facts(ThemeData theme, TextStyle? labelStyle) {
    return Wrap(
      spacing: 32,
      runSpacing: 12,
      children: [
        if (game.vndbRating != null)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('VNDB RATING', style: labelStyle),
              const SizedBox(height: 4),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: (game.vndbRating! / 10).toStringAsFixed(1),
                      style: theme.textTheme.titleMedium,
                    ),
                    if (game.vndbVotecount != null)
                      TextSpan(
                        text: ' · ${game.vndbVotecount} votes',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        if (game.released != null && game.released!.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('RELEASED', style: labelStyle),
              const SizedBox(height: 4),
              Text(game.released!, style: theme.textTheme.bodyLarge),
            ],
          ),
      ],
    );
  }
}

class _TagsSection extends ConsumerStatefulWidget {
  const _TagsSection({required this.game});

  final Game game;

  @override
  ConsumerState<_TagsSection> createState() => _TagsSectionState();
}

class _TagsSectionState extends ConsumerState<_TagsSection> {
  bool _adding = false;
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocus);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocus);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (!_focusNode.hasFocus && _adding) {
      setState(() {
        _adding = false;
        _controller.clear();
      });
    }
  }

  void _submit(String raw) {
    final tag = raw.trim();
    if (tag.isEmpty) return;
    final gameId = widget.game.id;
    final existing = widget.game.tags;
    if (existing.any((t) => t.toLowerCase() == tag.toLowerCase())) return;
    ref
        .read(gameEditorProvider)
        .update(gameId, (g) => g.tags = [...g.tags, tag]);
    _controller.clear();
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DetailSection(
      label: 'TAGS',
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final tag in widget.game.tags)
            Chip(
              label: Text(tag, style: theme.textTheme.labelMedium),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              deleteIcon: const Icon(Icons.close_rounded, size: 14),
              deleteButtonTooltipMessage: 'Remove $tag',
              onDeleted: () => ref.read(gameEditorProvider).update(
                  widget.game.id,
                  (g) => g.tags = [for (final t in g.tags) if (t != tag) t]),
            ),
          if (_adding)
            SizedBox(
              width: 140,
              child: Focus(
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.escape) {
                    setState(() {
                      _adding = false;
                      _controller.clear();
                    });
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'New tag',
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                  onSubmitted: _submit,
                ),
              ),
            )
          else
            ActionChip(
              label: const Text('+'),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              onPressed: () => setState(() => _adding = true),
            ),
        ],
      ),
    );
  }
}

class _MarkupSection extends ConsumerStatefulWidget {
  const _MarkupSection({
    required this.game,
    required this.label,
    required this.emptyHint,
    required this.editTooltip,
    required this.getValue,
    required this.setValue,
  });

  final Game game;
  final String label;
  final String emptyHint;
  final String editTooltip;
  final String Function(Game) getValue;
  final void Function(Game, String) setValue;

  @override
  ConsumerState<_MarkupSection> createState() => _MarkupSectionState();
}

class _MarkupSectionState extends ConsumerState<_MarkupSection> {
  bool _editing = false;
  bool _cancelled = false;
  String? _editGameId;
  GameEditor? _editor;
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocus);
  }

  @override
  void dispose() {
    // A game switch unmounts this section while the field still holds text;
    // the edit was captured for the original game, so save it there.
    if (_editing && !_cancelled && _editGameId != null) {
      final id = _editGameId!;
      final text = _controller.text;
      _editor?.update(id, (g) {
        widget.setValue(g, text);
      });
    }
    _focusNode.removeListener(_onFocus);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _begin() {
    _editor = ref.read(gameEditorProvider);
    setState(() {
      _editGameId = widget.game.id;
      _cancelled = false;
      _editing = true;
      _controller.text = widget.getValue(widget.game);
    });
  }

  void _onFocus() {
    if (!_focusNode.hasFocus && _editing && !_cancelled) {
      _save();
    }
  }

  void _save() {
    if (!mounted) return;
    final id = _editGameId;
    if (id == null) return;
    final text = _controller.text;
    setState(() => _editing = false);
    ref.read(gameEditorProvider).update(id, (g) {
      widget.setValue(g, text);
    });
  }

  void _cancel() {
    setState(() {
      _cancelled = true;
      _editing = false;
      _controller.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DetailSection(
      label: widget.label,
      actions: [
        if (!_editing)
          IconButton(
            tooltip: widget.editTooltip,
            icon: const Text('✎'),
            style: IconButton.styleFrom(
              minimumSize: const Size(28, 28),
              padding: EdgeInsets.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: _begin,
          ),
      ],
      child: _editing
          ? Focus(
              onKeyEvent: (node, event) {
                if (event is! KeyDownEvent) return KeyEventResult.ignored;
                if (event.logicalKey == LogicalKeyboardKey.escape) {
                  _cancel();
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.enter &&
                    HardwareKeyboard.instance.isControlPressed) {
                  _save();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                autofocus: true,
                maxLines: null,
                minLines: 4,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
            )
          : Builder(builder: (context) {
              final value = widget.getValue(widget.game);
              if (value.isEmpty) {
                return Text(
                  widget.emptyHint,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                );
              }
              if (widget.label == 'DESCRIPTION') {
                return DefaultTextStyle(
                  style: theme.textTheme.bodyMedium!.copyWith(height: 1.5),
                  child: VndbMarkupText(text: value),
                );
              }
              return Text(value, style: theme.textTheme.bodyMedium);
            }),
    );
  }
}
