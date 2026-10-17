// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../core/format.dart';
import '../../../../../core/model.dart';
import '../../../../../utils/prefs/app_prefs.dart' show tagFilterProvider;
import '../../../../../utils/theme/brand.dart';
import '../../../domain/cover_source.dart';
import '../../../domain/game_editor.dart';
import '../../../domain/library_query.dart';
import '../../../domain/vndb_markup.dart';

TextStyle? detailSectionLabelStyle(BuildContext context) {
  final theme = Theme.of(context);
  return theme.textTheme.labelSmall?.copyWith(
    color: theme.colorScheme.onSurfaceVariant,
    letterSpacing: 1.0,
  );
}

Widget detailSectionDivider(BuildContext context) => Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 16),
      child: Divider(
        height: 1,
        thickness: 1,
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
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
            Text(
              label,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            Flexible(
              child: Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: actions,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
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
    final blocks = <Widget>[];
    blocks.add(_facts(context, ref));
    if (game.tags.isNotEmpty) {
      blocks.add(_TagsSection(game: game));
    }
    if (game.vndbTags.isNotEmpty) {
      blocks.add(_VndbTagsSection(key: ValueKey(game.id), game: game));
    }
    blocks.add(_MarkupSection(
      game: game,
      label: 'Description',
      emptyHint: 'No description',
      editTooltip: 'Edit description',
      getValue: (g) => g.description,
      setValue: (g, v) => g.description = v,
    ));
    blocks.add(_MarkupSection(
      game: game,
      label: 'Notes',
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

  Widget _facts(BuildContext context, WidgetRef ref) {
    final seconds = game.totalPlaytimeSeconds;
    final language = _languageName(game.originalLanguage);
    final lengthMinutes = game.lengthMinutes;
    return Wrap(
      spacing: 28,
      runSpacing: 12,
      children: [
        if (game.developers.any((d) => d.name.isNotEmpty))
          DetailFact(
            label: 'Developer',
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (var i = 0; i < game.developers.length; i++)
                  if (game.developers[i].name.isNotEmpty) ...[
                    if (i > 0) const Text(', '),
                    _DeveloperLink(developer: game.developers[i]),
                  ],
              ],
            ),
          ),
        if (language != null)
          DetailFact(label: 'Language', child: Text(language)),
        if (lengthMinutes != null)
          DetailFact(label: 'Length', child: _lengthText(lengthMinutes, game.lengthVotes)),
        DetailFact(
          label: 'Played',
          child: Text(seconds > 0 ? formatPlaytime(seconds) : 'Never'),
        ),
      ],
    );
  }
}

const Map<String, String> _languageNames = {
  'ja': 'Japanese',
  'en': 'English',
  'zh': 'Chinese',
  'zh-Hant': 'Chinese (Traditional)',
  'ko': 'Korean',
  'ru': 'Russian',
  'de': 'German',
  'fr': 'French',
  'es': 'Spanish',
  'it': 'Italian',
  'pt-br': 'Portuguese (Brazil)',
  'pl': 'Polish',
  'uk': 'Ukrainian',
  'vi': 'Vietnamese',
  'th': 'Thai',
  'id': 'Indonesian',
};

String? _languageName(String? code) {
  if (code == null || code.isEmpty) return null;
  return _languageNames[code] ?? code;
}

/// Whole hours, rounded to the nearest; under an hour reads "<1 h".
Widget _lengthText(int minutes, int? votes) {
  final label = minutes < 60 ? '<1 h' : '~${(minutes / 60).round()} h';
  if (votes == null) return Text(label);
  return Tooltip(
    message: 'VNDB average from $votes votes',
    child: Text(label),
  );
}

/// A label above a value, used in the detail tabs' facts rows.
class DetailFact extends StatelessWidget {
  const DetailFact({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            fontSize: 11.5,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 3),
        DefaultTextStyle.merge(
          style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14),
          child: child,
        ),
      ],
    );
  }
}

class _DeveloperLink extends ConsumerWidget {
  const _DeveloperLink({required this.developer});

  final Developer developer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      onTap: () =>
          ref.read(developerFilterProvider.notifier).set(developer),
      child: Text(
        developer.name,
        style: const TextStyle(
          decoration: TextDecoration.underline,
          decorationStyle: TextDecorationStyle.dotted,
        ),
      ),
    );
  }
}

const List<(String, String)> _vndbTagGroups = [
  ('cont', 'Content'),
  ('tech', 'Technical'),
  ('ero', 'Sexual'),
];

class _VndbTagsSection extends ConsumerStatefulWidget {
  const _VndbTagsSection({super.key, required this.game});

  final Game game;

  @override
  ConsumerState<_VndbTagsSection> createState() => _VndbTagsSectionState();
}

class _VndbTagsSectionState extends ConsumerState<_VndbTagsSection> {
  var _showAll = false;
  var _showSpoilers = false;

  bool _keep(VndbTag tag) {
    if (tag.spoiler > 0 && !_showSpoilers) return false;
    return _showAll ? tag.rating > 0 : tag.rating >= 2.0;
  }

  @override
  Widget build(BuildContext context) {
    final tags = widget.game.vndbTags;
    final allCount = tags.where((t) => t.spoiler == 0 && t.rating > 0).length;
    final hasSpoilers = tags.any((t) => t.spoiler > 0);
    final linkStyle = _linkButtonStyle(Theme.of(context).colorScheme);
    return DetailSection(
      label: 'VNDB tags',
      actions: [
        TextButton(
          style: linkStyle,
          onPressed: () => setState(() => _showAll = !_showAll),
          child: Text(_showAll ? 'Show fewer' : 'Show all $allCount'),
        ),
        if (hasSpoilers)
          TextButton(
            style: linkStyle,
            onPressed: () => setState(() => _showSpoilers = !_showSpoilers),
            child: Text(_showSpoilers ? 'Hide spoilers' : 'Show spoilers'),
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (category, label) in _vndbTagGroups)
            ..._group(context, label, _visible(category)),
        ],
      ),
    );
  }

  List<VndbTag> _visible(String category) {
    final visible = [
      for (final tag in widget.game.vndbTags)
        if (tag.category == category && _keep(tag)) tag,
    ];
    visible.sort((a, b) => b.rating.compareTo(a.rating));
    return visible;
  }

  ButtonStyle _linkButtonStyle(ColorScheme scheme) => TextButton.styleFrom(
    foregroundColor: scheme.onSurfaceVariant,
    minimumSize: const Size(0, 28),
    padding: const EdgeInsets.symmetric(horizontal: 8),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    textStyle: const TextStyle(fontSize: 12.5),
  );

  List<Widget> _group(BuildContext context, String label, List<VndbTag> tags) {
    if (tags.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(label, style: detailSectionLabelStyle(context)),
      ),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [for (final tag in tags) _VndbTagChip(tag: tag)],
      ),
      const SizedBox(height: 12),
    ];
  }
}

class _VndbTagChip extends ConsumerWidget {
  const _VndbTagChip({required this.tag});

  final VndbTag tag;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: _kChipRadius,
      onTap: () =>
          ref.read(tagFilterProvider.notifier).set(vndbTagFilter(tag.name)),
      child: Container(
        height: _kChipHeight,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: _chipDecoration.copyWith(
          color: scheme.onSurface.withValues(alpha: 0.03),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (tag.spoiler > 0) ...[
              Icon(
                Icons.visibility_off_rounded,
                size: 12,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              tag.name,
              style: TextStyle(fontSize: 12.5, color: scheme.onSurface),
            ),
          ],
        ),
      ),
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
    return DetailSection(
      label: 'Tags',
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final tag in widget.game.tags)
            TagChip(
              label: tag,
              onRemove: () => ref.read(gameEditorProvider).update(
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
            InkWell(
              borderRadius: _kChipRadius,
              onTap: () => setState(() => _adding = true),
              child: Container(
                width: _kChipHeight,
                height: _kChipHeight,
                alignment: Alignment.center,
                decoration: _chipDecoration,
                child: Text(
                  '+',
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

const double _kChipHeight = 28;
final _kChipRadius = BorderRadius.circular(7);
final _chipDecoration = BoxDecoration(
  borderRadius: _kChipRadius,
  border: Border.all(color: OnImage.text.withValues(alpha: 0.14)),
);

class TagChip extends StatelessWidget {
  const TagChip({super.key, required this.label, required this.onRemove});

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: _kChipHeight,
      padding: const EdgeInsets.only(left: 11, right: 4),
      decoration: _chipDecoration,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12.5, color: scheme.onSurface),
          ),
          const SizedBox(width: 4),
          Tooltip(
            message: 'Remove $label',
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onRemove,
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  Icons.close_rounded,
                  size: 14,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
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

/// Four lines of description at 14 px with a 1.5 line height.
const double _kDescriptionCollapsedHeight = 4 * 14 * 1.5;

class _ExpandToggle extends StatelessWidget {
  const _ExpandToggle({required this.expanded, required this.onPressed});

  final bool expanded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: IconButton(
        tooltip: expanded ? 'Show less' : 'Show more',
        icon: Icon(
          expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
        ),
        onPressed: onPressed,
      ),
    );
  }
}

class _MarkupSectionState extends ConsumerState<_MarkupSection> {
  bool _editing = false;
  bool _cancelled = false;
  bool _expanded = false;
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
              if (widget.label == 'Description') {
                final style = theme.textTheme.bodyMedium!.copyWith(height: 1.5);
                final text = DefaultTextStyle(
                  style: style,
                  child: VndbMarkupText(text: value),
                );
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final painter = TextPainter(
                      text: TextSpan(
                        text: vndbPlainText(value),
                        style: style,
                      ),
                      maxLines: 4,
                      textDirection: Directionality.of(context),
                    )..layout(maxWidth: constraints.maxWidth);
                    final overflows = painter.didExceedMaxLines;
                    painter.dispose();
                    if (!overflows) return text;
                    if (_expanded) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          text,
                          _ExpandToggle(
                            expanded: true,
                            onPressed: () => setState(() => _expanded = false),
                          ),
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: _kDescriptionCollapsedHeight,
                          child: ClipRect(
                            child: OverflowBox(
                              alignment: Alignment.topLeft,
                              maxHeight: double.infinity,
                              child: text,
                            ),
                          ),
                        ),
                        _ExpandToggle(
                          expanded: false,
                          onPressed: () => setState(() => _expanded = true),
                        ),
                      ],
                    );
                  },
                );
              }
              return Text(value, style: theme.textTheme.bodyMedium);
            }),
    );
  }
}
