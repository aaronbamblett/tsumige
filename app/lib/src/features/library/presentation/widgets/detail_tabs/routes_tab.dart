// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart' hide Route;
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../core/model.dart';
import '../../../domain/game_editor.dart';
import 'info_tab.dart';

class RoutesTab extends ConsumerWidget {
  const RoutesTab({super.key, required this.game});

  final Game game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _HeaderRow(game: game),
          const SizedBox(height: 12),
          Row(
            children: [
              Text('Active route', style: detailSectionLabelStyle(context)),
              const SizedBox(width: 12),
              Expanded(
                child: _ActiveRouteDropdown(game: game),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (game.routes.isEmpty)
            Text(
              'No routes yet. Add the first one above.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            )
          else
            for (final route in game.routes)
              _RouteRow(
                key: ValueKey('route-${route.name}'),
                game: game,
                routeName: route.name,
                completed: route.completed,
              ),
        ],
      ),
    );
  }
}

class _HeaderRow extends ConsumerStatefulWidget {
  const _HeaderRow({required this.game});

  final Game game;

  @override
  ConsumerState<_HeaderRow> createState() => _HeaderRowState();
}

class _HeaderRowState extends ConsumerState<_HeaderRow> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add() {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Route name is required.');
      return;
    }
    if (widget.game.routes
        .any((r) => r.name.toLowerCase() == name.toLowerCase())) {
      setState(() => _error = 'That route already exists.');
      return;
    }
    setState(() => _error = null);
    _controller.clear();
    ref.read(gameEditorProvider).update(
          widget.game.id,
          (g) => g.routes = [...g.routes, Route(name: name)],
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${widget.game.routes.length} routes',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const Key('routes-new-name'),
                controller: _controller,
                decoration: InputDecoration(
                  hintText: 'New route',
                  isDense: true,
                  border: const OutlineInputBorder(),
                  errorText: _error,
                ),
                onSubmitted: (_) => _add(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: const Key('routes-add'),
              onPressed: _add,
              child: const Text('Add'),
            ),
          ],
        ),
      ],
    );
  }
}

class _ActiveRouteDropdown extends ConsumerWidget {
  const _ActiveRouteDropdown({required this.game});

  final Game game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DropdownButton<String?>(
      key: const Key('routes-active'),
      value: game.routes.any((r) => r.name == game.activeRoute)
          ? game.activeRoute
          : null,
      isExpanded: true,
      items: [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('No active route'),
        ),
        for (final route in game.routes)
          DropdownMenuItem<String?>(
            value: route.name,
            child: Text(route.name),
          ),
      ],
      onChanged: (value) => ref
          .read(gameEditorProvider)
          .update(game.id, (g) => g.activeRoute = value),
    );
  }
}

class _RouteRow extends ConsumerStatefulWidget {
  const _RouteRow(
      {super.key,
      required this.game,
      required this.routeName,
      required this.completed});

  final Game game;
  final String routeName;
  final bool completed;

  @override
  ConsumerState<_RouteRow> createState() => _RouteRowState();
}

class _RouteRowState extends ConsumerState<_RouteRow> {
  bool _editing = false;
  String? _error;
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

  void _begin() {
    setState(() {
      _editing = true;
      _error = null;
      _controller.text = widget.routeName;
    });
  }

  void _onFocus() {
    if (!_focusNode.hasFocus && _editing) _save();
  }

  void _save() {
    if (!mounted) return;
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Route name is required.');
      return;
    }
    final oldName = widget.routeName;
    if (name.toLowerCase() != oldName.toLowerCase() &&
        widget.game.routes
            .any((r) => r.name.toLowerCase() == name.toLowerCase())) {
      setState(() => _error = 'That route already exists.');
      return;
    }
    setState(() {
      _editing = false;
      _error = null;
    });
    if (name == oldName) return;
    ref.read(gameEditorProvider).update(widget.game.id, (g) {
      for (final route in g.routes) {
        if (route.name == oldName) route.name = name;
      }
      if (g.activeRoute == oldName) g.activeRoute = name;
    });
  }

  void _cancel() {
    setState(() {
      _editing = false;
      _error = null;
      _controller.clear();
    });
  }

  Future<void> _delete() async {
    if (widget.completed) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          content: Text(
              "Delete route ${widget.routeName}? It's marked completed."),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor:
                    Theme.of(dialogContext).colorScheme.error,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    final name = widget.routeName;
    await ref.read(gameEditorProvider).update(widget.game.id, (g) {
      g.routes.removeWhere((r) => r.name == name);
      if (g.activeRoute == name) g.activeRoute = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_editing) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Focus(
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            if (event.logicalKey == LogicalKeyboardKey.escape) {
              _cancel();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: TextField(
            key: const Key('route-rename-field'),
            controller: _controller,
            focusNode: _focusNode,
            autofocus: true,
            decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(),
              errorText: _error,
            ),
            onSubmitted: (_) => _save(),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Checkbox(
            key: ValueKey('route-completed-${widget.routeName}'),
            value: widget.completed,
            onChanged: (value) {
              if (value == null) return;
              final name = widget.routeName;
              ref.read(gameEditorProvider).update(widget.game.id, (g) {
                for (final route in g.routes) {
                  if (route.name == name) route.completed = value;
                }
              });
            },
          ),
          Expanded(
            child: GestureDetector(
              onDoubleTap: _begin,
              child: Text(widget.routeName),
            ),
          ),
          IconButton(
            key: ValueKey('route-rename-${widget.routeName}'),
            tooltip: 'Rename ${widget.routeName}',
            icon: const Text('✎'),
            style: IconButton.styleFrom(
              minimumSize: const Size(28, 28),
              padding: EdgeInsets.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: _begin,
          ),
          IconButton(
            key: ValueKey('route-delete-${widget.routeName}'),
            tooltip: 'Delete ${widget.routeName}',
            icon: const Icon(Icons.delete_outline_rounded),
            style: IconButton.styleFrom(
              minimumSize: const Size(28, 28),
              padding: EdgeInsets.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: _delete,
          ),
        ],
      ),
    );
  }
}
