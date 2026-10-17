// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/covers.dart';
import '../../../../core/model.dart';
import '../../../../core/vndb.dart';
import '../../../../utils/theme/brand.dart';
import '../../../../utils/toast.dart';
import '../../data/library_repository.dart';
import '../../domain/add_game.dart';
import '../../domain/game_editor.dart';
import '../../domain/runner_detection.dart';
import '../../domain/selection.dart';
import '../widgets/detail_tabs/launch_tab.dart';

Future<void> showAddGameDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const AddGameDialog(),
  );
}

class AddGameDialog extends ConsumerStatefulWidget {
  const AddGameDialog({super.key});

  @override
  ConsumerState<AddGameDialog> createState() => _AddGameDialogState();
}

class _AddGameDialogState extends ConsumerState<AddGameDialog> {
  int _step = 0;
  bool _manual = false;
  late final TextEditingController _query;
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _tags;
  late final TextEditingController _exe;
  late final TextEditingController _steamAppId;
  late LaunchMode _mode;
  Timer? _debounce;
  int _searchToken = 0;
  bool _loading = false;
  bool _searched = false;
  String? _searchError;
  List<VnSearchResult> _results = const [];
  VnSearchResult? _picked;
  bool _saving = false;
  String? _formError;

  @override
  void initState() {
    super.initState();
    _query = TextEditingController();
    _title = TextEditingController();
    _description = TextEditingController();
    _tags = TextEditingController();
    _exe = TextEditingController();
    _steamAppId = TextEditingController();
    _mode = LaunchMode.proton;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    _title.dispose();
    _description.dispose();
    _tags.dispose();
    _exe.dispose();
    _steamAppId.dispose();
    super.dispose();
  }

  Set<String> _libraryVndbIds() {
    final games = ref.watch(libraryProvider).value?.library.games;
    if (games == null) return const {};
    return {for (final game in games) if (game.vndbId != null) game.vndbId!};
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _loading = false;
        _searched = false;
        _searchError = null;
        _results = const [];
      });
      return;
    }
    _debounce =
        Timer(const Duration(milliseconds: 400), () => _runSearch(query));
  }

  Future<void> _runSearch(String query) async {
    if (query.isEmpty) return;
    final token = ++_searchToken;
    final client = ref.read(vndbSearchClientProvider);
    setState(() {
      _loading = true;
      _searchError = null;
    });
    List<VnSearchResult> results;
    try {
      results = await client.search(query);
    } catch (e) {
      if (!mounted || token != _searchToken) return;
      setState(() {
        _loading = false;
        _searchError = '$e';
      });
      return;
    }
    if (!mounted || token != _searchToken) return;
    setState(() {
      _loading = false;
      _searched = true;
      _results = results;
    });
  }

  void _pick(VnSearchResult result) {
    _title.text = result.title;
    _description.text = result.description;
    _tags.text = result.tags.join(', ');
    setState(() {
      _picked = result;
      _manual = false;
      _formError = null;
      _step = 1;
    });
  }

  void _startManual() {
    _title.text = '';
    _description.text = '';
    _tags.text = '';
    setState(() {
      _picked = null;
      _manual = true;
      _formError = null;
      _step = 1;
    });
  }

  Future<void> _chooseExe() async {
    final picked = await ref
        .read(pathPickerProvider)(mode: PathPickMode.file);
    if (picked == null || picked.isEmpty || !mounted) return;
    if (isPortalPath(picked)) {
      Toast(context).show(portalPathMessage);
      return;
    }
    _exe.text = picked;
  }

  Future<void> _add() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _formError = 'Title is required');
      return;
    }
    final exe = _exe.text.trim();
    if (_mode != LaunchMode.steam && exe.isEmpty) {
      setState(() => _formError = 'Executable is required');
      return;
    }
    if (exe.isNotEmpty && isPortalPath(exe)) {
      if (mounted) {
        Toast(context).show(portalPathMessage);
        setState(() => _formError = portalPathMessage);
      }
      return;
    }
    int? steamAppId;
    final steamRaw = _steamAppId.text.trim();
    if (_mode == LaunchMode.steam && steamRaw.isNotEmpty) {
      steamAppId = int.tryParse(steamRaw);
      if (steamAppId == null) {
        setState(() => _formError = 'Steam App ID must be digits.');
        return;
      }
    }
    setState(() {
      _saving = true;
      _formError = null;
    });
    final picked = _manual ? null : _picked;
    final Game game;
    if (picked != null) {
      game = gameFromVn(picked, exe: exe, mode: _mode);
      game.title = title;
      game.description = _description.text;
      game.tags = parseTagsField(_tags.text);
      await fillVndbMetadata(game, ref.read(vndbSearchClientProvider));
    } else {
      game = Game(
        id: const Uuid().v4(),
        title: title,
        description: _description.text,
        tags: parseTagsField(_tags.text),
        addedAt: DateTime.now().toUtc(),
        launch: LaunchOverrides(
          mode: _mode,
          executable: exe.isEmpty ? null : exe,
        ),
      );
    }
    game.launch.steamAppId = steamAppId;
    var coverFailed = false;
    final imageUrl = picked?.imageUrl;
    if (imageUrl != null && imageUrl.isNotEmpty) {
      try {
        final response = await ref
            .read(addGameHttpClientProvider)
            .get(Uri.parse(imageUrl));
        if (response.statusCode != 200) {
          throw StateError('HTTP ${response.statusCode}');
        }
        final dir = ref.read(dataDirProvider);
        final name =
            await storeOriginal(dir, game.id, response.bodyBytes);
        game.cover = name;
        await generateThumbnails(dir, [(game.id, name)]);
      } catch (_) {
        coverFailed = true;
      }
    }
    if (!mounted) return;
    await ref.read(gameEditorProvider).add(game, context: context);
    ref.read(selectedGameIdProvider.notifier).select(game.id);
    if (!mounted) return;
    Toast(context).show(
        coverFailed ? 'Added $title (cover download failed)' : 'Added $title');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        width: 720,
        height: 640,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _step == 0 ? _searchStep(context) : _setupStep(context),
        ),
      ),
    );
  }

  Widget _searchStep(BuildContext context) {
    final theme = Theme.of(context);
    final inLibrary = _libraryVndbIds();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Find on VNDB', style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
        TextField(
          key: const Key('add-game-search'),
          controller: _query,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: _onQueryChanged,
          onSubmitted: (value) {
            _debounce?.cancel();
            _runSearch(value.trim());
          },
          decoration: const InputDecoration(
            hintText: 'Search VNDB',
            prefixIcon: Icon(Icons.search_rounded),
            border: OutlineInputBorder(),
          ),
        ),
        if (_loading) const LinearProgressIndicator(),
        const SizedBox(height: 8),
        Expanded(child: _resultsBody(context, inLibrary)),
        TextButton(
          key: const Key('add-game-manual'),
          onPressed: _startManual,
          child: const Text('Not on VNDB? Add manually'),
        ),
      ],
    );
  }

  Widget _resultsBody(BuildContext context, Set<String> inLibrary) {
    final theme = Theme.of(context);
    if (_searchError != null) {
      return Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                _searchError!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              key: const Key('add-game-retry'),
              onPressed: () {
                _debounce?.cancel();
                _runSearch(_query.text.trim());
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (!_searched) {
      return Center(
        child: Text(
          'Type to search VNDB',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    if (_results.isEmpty && !_loading) {
      return const Center(child: Text('No matches on VNDB'));
    }
    return ListView.builder(
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final result = _results[index];
        final owned = inLibrary.contains(result.id);
        return _ResultRow(
          result: result,
          owned: owned,
          onPick: owned ? null : () => _pick(result),
        );
      },
    );
  }

  Widget _setupStep(BuildContext context) {
    final theme = Theme.of(context);
    final picked = _manual ? null : _picked;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Set it up', style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
        Row(
          children: [
            _CoverThumb(
                imageUrl: picked?.imageUrl,
                sexual: picked?.imageSexual ?? 0),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                picked?.title ?? 'New game',
                style: theme.textTheme.titleMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const Key('add-game-title'),
                  controller: _title,
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('add-game-description'),
                  controller: _description,
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('add-game-tags'),
                  controller: _tags,
                  decoration: const InputDecoration(
                    labelText: 'Tags',
                    hintText: 'Comma-separated',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('add-game-exe'),
                        controller: _exe,
                        decoration: const InputDecoration(
                          labelText: 'Executable',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      key: const Key('add-game-exe-choose'),
                      onPressed: _chooseExe,
                      child: const Text('Choose…'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButton<LaunchMode>(
                  key: const Key('add-game-mode'),
                  value: _mode,
                  isExpanded: true,
                  items: [
                    for (final mode in LaunchMode.values)
                      DropdownMenuItem(
                        value: mode,
                        child: Text(launchModeName(mode)),
                      ),
                  ],
                  onChanged: (mode) {
                    if (mode != null) setState(() => _mode = mode);
                  },
                ),
                if (_mode == LaunchMode.steam) ...[
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('add-game-steam-app-id'),
                    controller: _steamAppId,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Steam App ID',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                if (_formError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _formError!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            BrandGlassButton(
              key: const Key('add-game-back'),
              height: 40,
              expand: false,
              onPressed: _saving ? null : () => setState(() => _step = 0),
              label: const Text('Back'),
            ),
            const Spacer(),
            BrandButton(
              key: const Key('add-game-add'),
              height: 40,
              expand: false,
              onPressed: _saving ? null : _add,
              label: const Text('Add'),
            ),
          ],
        ),
      ],
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.result, required this.owned, this.onPick});

  final VnSearchResult result;
  final bool owned;
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final year = _year(result.released);
    final meta = [
      if (year.isNotEmpty) year,
      if (result.developers.isNotEmpty) result.developers.join(', '),
    ].join(' · ');
    return ListTile(
      enabled: !owned,
      leading: _CoverThumb(
          imageUrl: result.imageUrl, sexual: result.imageSexual),
      title: Text(result.title),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (result.alttitle != null && result.alttitle!.isNotEmpty)
            Text(
              result.alttitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          if (meta.isNotEmpty) Text(meta),
          if (result.rating != null)
            Text('VNDB Rating ${(result.rating! / 10).toStringAsFixed(1)}'),
        ],
      ),
      trailing: owned ? const Text('In library') : null,
      onTap: onPick,
    );
  }
}

String _year(String? released) {
  if (released == null || released.isEmpty) return '';
  final match = RegExp(r'^\d{4}').firstMatch(released);
  return match?.group(0) ?? released;
}

class _CoverThumb extends StatelessWidget {
  const _CoverThumb({required this.imageUrl, required this.sexual});

  final String? imageUrl;
  final int sexual;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    Widget art = const Icon(Icons.image_not_supported_outlined);
    if (url != null && url.isNotEmpty) {
      art = Image.network(
        url,
        width: 48,
        height: 68,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            const Icon(Icons.broken_image_outlined),
      );
      if (sexual >= 1) {
        art = ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: art,
        );
      }
    }
    return SizedBox(
      width: 48,
      height: 68,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: art,
      ),
    );
  }
}
