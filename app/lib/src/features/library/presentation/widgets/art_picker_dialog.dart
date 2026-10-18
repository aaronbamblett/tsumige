// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../../core/model.dart';
import '../../../../core/paths.dart';
import '../../../../core/steamgriddb.dart';
import '../../../../core/vndb.dart';
import '../../../../utils/prefs/app_prefs.dart';
import '../../../../utils/theme/brand.dart';
import '../../../../utils/toast.dart';
import '../../../../widgets/tsumige_logo.dart';
import '../../data/library_repository.dart';
import '../../domain/cover_source.dart';
import '../../domain/add_game.dart';
import '../../domain/game_editor.dart';
import 'art_image.dart';
import 'art_overlay.dart';
import 'art_store.dart';
import 'detail_tabs/related_tab.dart';
import 'dialog_shell.dart';
import 'game_cover_grid_delegate.dart';
import 'library_toolbar.dart';

/// Opens the Cover and Background picker over the current screen.
Future<void> showArtPickerDialog(BuildContext context, Game game) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (context) =>
        ArtPickerDialog(game: game, size: dialogShellSize(context)),
  );
}

enum _ArtTab { cover, background }

/// A pending choice, applied only by Save.
sealed class _Pick {
  const _Pick();
}

final class _RemotePick extends _Pick {
  const _RemotePick(this.art);

  final ArtCandidate art;
}

final class _FilePick extends _Pick {
  const _FilePick(this.path);

  final String path;
}

/// Background only: drop the background and fall back to the cover.
final class _ClearPick extends _Pick {
  const _ClearPick();
}

class ArtPickerDialog extends ConsumerStatefulWidget {
  const ArtPickerDialog({super.key, required this.game, required this.size});

  final Game game;
  final Size size;

  @override
  ConsumerState<ArtPickerDialog> createState() => _ArtPickerDialogState();
}

class _ArtPickerDialogState extends ConsumerState<ArtPickerDialog> {
  var _tab = _ArtTab.cover;
  _Pick? _coverPick;
  _Pick? _backgroundPick;
  ArtCandidates? _candidates;
  Future<ArtCandidates>? _art;
  var _saving = false;
  final _scroll = ScrollController();

  /// SteamGridDB Steam IDs, name-search results and the picked search game,
  /// shared by the Cover and Background tabs so one dialog looks them up once.
  late final _sgdb = _SgdbShared();

  @override
  void initState() {
    super.initState();
    if (widget.game.vndbId != null) _load();
  }

  @override
  void dispose() {
    _sgdb.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _load() {
    final future = ref
        .read(vndbSearchClientProvider)
        .fetchArtCandidates(widget.game.vndbId!);
    _candidates = null;
    _art = future;
    future.then((art) {
      if (mounted) setState(() => _candidates = art);
    }, onError: (_) {});
  }

  bool get _hasBackground => widget.game.background?.isNotEmpty ?? false;

  _Pick? get _activePick =>
      _tab == _ArtTab.cover ? _coverPick : _backgroundPick;

  void _setActivePick(_Pick pick) => setState(() {
    if (_tab == _ArtTab.cover) {
      _coverPick = pick;
    } else {
      _backgroundPick = pick;
    }
  });

  void _close() => Navigator.of(context).pop();

  Future<void> _pickFile() async {
    final picked = await ref.read(coverPickerProvider)();
    if (picked == null || picked.isEmpty || !mounted) return;
    if (picked.startsWith('/run/user/')) {
      Toast(context).show(
        'That file came through the Flatpak portal. '
        'Pick it from its real location.',
      );
      return;
    }
    _setActivePick(_FilePick(picked));
  }

  Future<List<int>> _download(String url) async {
    final response = await ref
        .read(addGameHttpClientProvider)
        .get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
    }
    return response.bodyBytes;
  }

  Future<List<int>> _bytesFor(_Pick pick) => switch (pick) {
    _RemotePick(:final art) => _download(art.url),
    _FilePick(:final path) => File(path).readAsBytes(),
    _ClearPick() => throw StateError('a cleared background has no bytes'),
  };

  /// The VNDB url a pick came from, or `file` for a local file.
  String _sourceOf(_Pick pick) => switch (pick) {
    _RemotePick(:final art) => art.url,
    _FilePick() => 'file',
    _ClearPick() => throw StateError('a cleared background has no source'),
  };

  Future<void> _save() async {
    final cover = _coverPick;
    final background = _backgroundPick;
    final game = widget.game;
    if (cover == null && background == null) {
      _close();
      return;
    }
    setState(() => _saving = true);
    try {
      final coverBytes = cover == null ? null : await _bytesFor(cover);
      final backgroundBytes = background == null || background is _ClearPick
          ? null
          : await _bytesFor(background);
      if (!mounted) return;
      if (cover != null && coverBytes != null) {
        await storeCoverBytes(context, ref, game, coverBytes, _sourceOf(cover));
        if (!mounted) return;
        setState(() => _coverPick = null);
      }
      if (!mounted) return;
      if (background is _ClearPick) {
        await clearBackground(context, ref, game);
      } else if (background != null && backgroundBytes != null) {
        await storeBackgroundBytes(
          context,
          ref,
          game,
          backgroundBytes,
          _sourceOf(background),
        );
      }
      if (mounted) _close();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      Toast(context).showError("Couldn't use that image: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return DialogShell(
      frameKey: const Key('art-picker'),
      size: widget.size,
      eyebrow: 'Change art',
      title: widget.game.title,
      onClose: _close,
      closeKey: const Key('art-picker-close'),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _left()),
          _preview(context),
        ],
      ),
      footer: _footer(),
    );
  }

  Widget _left() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 0, 0),
          child: ToolbarBox(
            width: 200,
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: Row(
                children: [
                  Expanded(
                    child: ToolbarSegment(
                      label: 'Cover',
                      selected: _tab == _ArtTab.cover,
                      onTap: () => setState(() => _tab = _ArtTab.cover),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    child: ToolbarSegment(
                      label: 'Background',
                      selected: _tab == _ArtTab.background,
                      onTap: () => setState(() => _tab = _ArtTab.background),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: Scrollbar(
            controller: _scroll,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
              child: _body(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _body() {
    if (widget.game.vndbId == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _note('No VNDB id, so pick a file.'),
          if (_tab == _ArtTab.cover)
            _steamGridDbSection()
          else
            _steamGridDbHeroesSection(),
        ],
      );
    }
    // One FutureBuilder for both tabs, so a tab switch keeps the snapshot.
    return FutureBuilder<ArtCandidates>(
      future: _art,
      builder: (context, snapshot) {
        final vndb = _vndbSnapshot(
          snapshot,
          background: _tab == _ArtTab.background,
        );
        if (_tab == _ArtTab.background) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [vndb, _steamGridDbHeroesSection()],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [vndb, _steamGridDbSection()],
        );
      },
    );
  }

  Widget _steamGridDbSection() => _SteamGridDbSection(
    key: const ValueKey('sgdb-grids'),
    game: widget.game,
    kind: _SgdbKind.grids,
    shared: _sgdb,
    selectedUrl: _coverPick is _RemotePick
        ? (_coverPick as _RemotePick).art.url
        : null,
    isCurrent: _isCurrentCover,
    onPick: (art) => setState(() => _coverPick = _RemotePick(art)),
  );

  Widget _steamGridDbHeroesSection() => _SteamGridDbSection(
    key: const ValueKey('sgdb-heroes'),
    game: widget.game,
    kind: _SgdbKind.heroes,
    shared: _sgdb,
    selectedUrl: _backgroundPick is _RemotePick
        ? (_backgroundPick as _RemotePick).art.url
        : null,
    isCurrent: _isCurrentBackground,
    onPick: (art) => setState(() => _backgroundPick = _RemotePick(art)),
  );

  Widget _vndbSnapshot(
    AsyncSnapshot<ArtCandidates> snapshot, {
    required bool background,
  }) {
    if (snapshot.hasError) {
      return Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Couldn't reach VNDB."),
            const SizedBox(height: 12),
            BrandGlassButton(
              height: 40,
              expand: false,
              onPressed: () => setState(_load),
              label: const Text('Try again'),
            ),
          ],
        ),
      );
    }
    final art = snapshot.data;
    if (art == null) {
      return const Padding(
        padding: EdgeInsets.only(top: 48),
        child: Center(child: TsumigeLogoShimmer(size: 48)),
      );
    }
    return background ? _backgroundSections(art) : _coverSections(art);
  }

  Widget _note(String text) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Text(text, style: TextStyle(color: scheme.onSurfaceVariant)),
    );
  }

  Widget _coverSections(ArtCandidates art) {
    final main = art.main;
    return _section(
      'VNDB covers and packages',
      [
        ?main,
        ...art.releaseImages.where((i) => i.portrait),
        ...art.releaseImages.where((i) => !i.portrait),
      ],
      columns: 5,
      aspectRatio: kGameCoverAspectRatio,
      isCurrent: _isCurrentCover,
    );
  }

  Widget _backgroundSections(ArtCandidates art) {
    final main = art.main;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _section(
          'VNDB screenshots',
          art.screenshots,
          columns: 3,
          aspectRatio: 440 / 340,
          isCurrent: _isCurrentBackground,
        ),
        _section(
          'VNDB artwork',
          [?main, ...art.releaseImages.where((i) => !i.portrait)],
          columns: 3,
          aspectRatio: 440 / 340,
          isCurrent: _isCurrentBackground,
        ),
      ],
    );
  }

  /// Whether [art] is the cover or background the game uses now. A game with
  /// a cover and no recorded source predates source tracking: its cover came
  /// from VNDB's main image.
  bool _isCurrentCover(ArtCandidate art) {
    final source = widget.game.coverSource;
    if (source != null) return art.url == source;
    final hasCover = widget.game.cover?.isNotEmpty ?? false;
    return hasCover && art.url == _candidates?.main?.url;
  }

  /// The pane shows the cover when no background is set.
  bool _isCurrentBackground(ArtCandidate art) => _hasBackground
      ? art.url == widget.game.backgroundSource
      : _isCurrentCover(art);

  Widget _section(
    String label,
    List<ArtCandidate> items, {
    required int columns,
    required double aspectRatio,
    required bool Function(ArtCandidate) isCurrent,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final active = _activePick;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              Text(
                '${items.length}',
                style: TextStyle(
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 14.0;
            final columnWidth =
                (constraints.maxWidth - spacing * (columns - 1)) / columns;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: spacing,
                mainAxisSpacing: spacing,
                mainAxisExtent:
                    columnWidth / aspectRatio + _kArtCaptionExtent,
              ),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final art = items[index];
                return _ArtTile(
                  key: ValueKey('art-${art.url}'),
                  art: art,
                  aspectRatio: aspectRatio,
                  selected:
                      active is _RemotePick && active.art.url == art.url,
                  current: isCurrent(art),
                  onTap: () => _setActivePick(_RemotePick(art)),
                );
              },
            );
          },
        ),
      ],
    );
  }

  Widget _preview(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dir = ref.watch(dataDirProvider);
    return Container(
      width: 300,
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
        child: _tab == _ArtTab.cover
            ? _coverPreview(context, dir)
            : _backgroundPreview(context, dir),
      ),
    );
  }

  Widget _coverPreview(BuildContext context, DataDir dir) {
    final scheme = Theme.of(context).colorScheme;
    final pick = _coverPick;
    final cover = widget.game.cover;
    final Widget image;
    if (pick != null) {
      image = _pickImage(pick);
    } else if (cover != null && cover.isNotEmpty) {
      image = _storedImage(p.join(dir.coversOriginal.path, cover));
    } else {
      image = ColoredBox(color: scheme.surface);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'In the library',
          style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: 220,
          child: AspectRatio(
            aspectRatio: kGameCoverAspectRatio,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: image,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          widget.game.title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        Text(
          'Covers are cropped to 2:3 in the grid.',
          style: TextStyle(fontSize: 12, color: scheme.outline),
        ),
      ],
    );
  }

  Widget _backgroundPreview(BuildContext context, DataDir dir) {
    final scheme = Theme.of(context).colorScheme;
    final game = widget.game;
    final pick = _backgroundPick;
    final Widget image;
    if (pick != null && pick is! _ClearPick) {
      image = _pickImage(pick);
    } else if (pick == null && _hasBackground) {
      image = _storedImage(p.join(dir.coversBackground.path, game.background!));
    } else if (game.cover != null && game.cover!.isNotEmpty) {
      image = _storedImage(p.join(dir.coversOriginal.path, game.cover!));
    } else {
      image = ColoredBox(color: scheme.surface);
    }
    final picked =
        (pick != null && pick is! _ClearPick) ||
        (pick == null && _hasBackground);
    final original = game.vndbOriginalTitle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'In the details pane',
          style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 10),
        Container(
          width: 252,
          height: 195,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              image,
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      scheme.surfaceContainer.withValues(alpha: 0),
                      scheme.surfaceContainer.withValues(alpha: 0.55),
                      scheme.surfaceContainer,
                    ],
                    stops: const [0.35, 0.62, 1.0],
                  ),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 10,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      game.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: OnImage.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        shadows: [
                          Shadow(
                            offset: Offset(0, 2),
                            blurRadius: 10,
                            color: Color(0xB3000000),
                          ),
                        ],
                      ),
                    ),
                    if (original != null &&
                        original.isNotEmpty &&
                        original != game.title)
                      Text(
                        original,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (!picked) ...[
          const SizedBox(height: 10),
          Text(
            'No background picked, so the pane uses the cover.',
            style: TextStyle(fontSize: 12, color: scheme.outline),
          ),
        ],
      ],
    );
  }

  Widget _pickImage(_Pick pick) => switch (pick) {
    _RemotePick(:final art) => Image.network(
      art.thumbnail,
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    ),
    _FilePick(:final path) => _storedImage(path),
    _ClearPick() => const SizedBox.shrink(),
  };

  Widget _storedImage(String path) => Image(
    image: artFileImage(
      File(path),
      version: ref.watch(artVersionProvider)(path),
    ),
    fit: BoxFit.cover,
    alignment: Alignment.topCenter,
    gaplessPlayback: true,
    errorBuilder: (_, _, _) => const SizedBox.shrink(),
  );

  Widget _footer() {
    final candidates = _candidates;
    final main = candidates?.main;
    final Widget? reset;
    if (_tab == _ArtTab.cover) {
      reset = widget.game.vndbId == null
          ? null
          : BrandGlassButton(
              height: 40,
              expand: false,
              onPressed: main == null
                  ? null
                  : () => _setActivePick(_RemotePick(main)),
              icon: const Icon(Icons.restore_rounded),
              label: const Text('Use VNDB cover'),
            );
    } else {
      reset = _hasBackground || _backgroundPick != null
          ? BrandGlassButton(
              height: 40,
              expand: false,
              onPressed: () =>
                  setState(() => _backgroundPick = const _ClearPick()),
              icon: const Icon(Icons.restore_rounded),
              label: const Text('Use the cover'),
            )
          : null;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      child: Row(
        children: [
          BrandGlassButton(
            height: 40,
            expand: false,
            onPressed: _pickFile,
            icon: const Icon(Icons.folder_outlined),
            label: const Text('From file…'),
          ),
          if (reset != null) ...[const SizedBox(width: 10), reset],
          const Spacer(),
          BrandGlassButton(
            height: 40,
            expand: false,
            onPressed: _close,
            label: const Text('Cancel'),
          ),
          const SizedBox(width: 10),
          BrandButton(
            height: 40,
            expand: false,
            loading: _saving,
            onPressed: _save,
            label: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

/// Which SteamGridDB art a section shows: covers on the Cover tab, heroes
/// (wide banners) on the Background tab.
enum _SgdbKind {
  grids,
  heroes;

  String get noKeyMessage => switch (this) {
    grids =>
      'Covers from SteamGridDB need your own free API key. '
      'Get one in your SteamGridDB preferences.',
    heroes =>
      'Backgrounds from SteamGridDB need your own free API key. '
      'Get one in your SteamGridDB preferences.',
  };

  String get emptyMessage => switch (this) {
    grids => 'No SteamGridDB covers for this game.',
    heroes => 'No SteamGridDB backgrounds for this game.',
  };

  int get columns => switch (this) {
    grids => 5,
    heroes => 3,
  };

  double get aspectRatio => switch (this) {
    grids => kGameCoverAspectRatio,
    heroes => 440 / 340,
  };

  Future<List<ArtCandidate>> fetchSteam(
    SteamGridDbClient client,
    int appId,
  ) => switch (this) {
    grids => client.gridsForSteamApp(appId),
    heroes => client.heroesForSteamApp(appId),
  };

  Future<List<ArtCandidate>> fetchGame(
    SteamGridDbClient client,
    int gameId,
  ) => switch (this) {
    grids => client.gridsForGame(gameId),
    heroes => client.heroesForGame(gameId),
  };
}

/// SteamGridDB lookup shared by the Cover and Background tabs. The Steam IDs,
/// the name-search results and the picked search game are resolved once per
/// dialog; each kind of art (covers, heroes) is then fetched once for that
/// lookup. The in-flight lookup is shared by both tabs, with one in-flight
/// fetch per kind, so a tab switch joins pending work instead of repeating
/// it. A lookup generation plus one generation per kind keeps a stale
/// response from landing: the lookup never invalidates a kind fetch, and a
/// kind fetch never invalidates the lookup or the other kind.
class _SgdbShared extends ChangeNotifier {
  List<int>? steamIds;
  List<SteamGridDbGame>? search;
  int? selectedSearchId;
  var grids = const <ArtCandidate>[];
  var heroes = const <ArtCandidate>[];
  var gridsLoading = false;
  var heroesLoading = false;
  String? gridsError;
  String? heroesError;

  /// Which game plus key the lookup above was resolved for.
  var lookupFor = '';

  /// Which lookup plus search selection each kind of art was loaded for.
  var gridsFor = '';
  var heroesFor = '';

  var _lookupGeneration = 0;
  var _gridsGeneration = 0;
  var _heroesGeneration = 0;
  Future<void>? _lookupFuture;
  var _lookupPrint = '';
  Future<void>? _gridsFuture;
  Future<void>? _heroesFuture;

  /// Why the shared lookup failed: 'badKey' or 'network'.
  String? _lookupError;

  var _disposed = false;

  static String fingerprint(Game game, String key) =>
      '${game.id}|${key.trim()}';

  List<ArtCandidate> artFor(_SgdbKind kind) =>
      kind == _SgdbKind.grids ? grids : heroes;

  bool loadingFor(_SgdbKind kind) =>
      kind == _SgdbKind.grids ? gridsLoading : heroesLoading;

  String? errorFor(_SgdbKind kind) =>
      kind == _SgdbKind.grids ? gridsError : heroesError;

  String loadedFor(_SgdbKind kind) =>
      kind == _SgdbKind.grids ? gridsFor : heroesFor;

  /// True while the shared Steam ID / name-search lookup is running.
  bool get lookupPending => _lookupFuture != null;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  int _kindGeneration(_SgdbKind kind) =>
      kind == _SgdbKind.grids ? _gridsGeneration : _heroesGeneration;

  Future<void>? _kindFuture(_SgdbKind kind) =>
      kind == _SgdbKind.grids ? _gridsFuture : _heroesFuture;

  void _setKindFuture(_SgdbKind kind, Future<void>? future) {
    if (kind == _SgdbKind.grids) {
      _gridsFuture = future;
    } else {
      _heroesFuture = future;
    }
  }

  bool _fetchStale(_SgdbKind kind, int generation) =>
      _disposed || generation != _kindGeneration(kind);

  void reset() {
    _lookupGeneration++;
    _gridsGeneration++;
    _heroesGeneration++;
    _lookupFuture = null;
    _lookupPrint = '';
    _lookupError = null;
    _gridsFuture = null;
    _heroesFuture = null;
    steamIds = null;
    search = null;
    selectedSearchId = null;
    grids = const [];
    heroes = const [];
    gridsLoading = false;
    heroesLoading = false;
    gridsError = null;
    heroesError = null;
    lookupFor = '';
    gridsFor = '';
    heroesFor = '';
    _notify();
  }

  void _setLoading(_SgdbKind kind, bool value) {
    if (kind == _SgdbKind.grids) {
      gridsLoading = value;
    } else {
      heroesLoading = value;
    }
  }

  void _setError(_SgdbKind kind, String? value) {
    if (kind == _SgdbKind.grids) {
      gridsError = value;
    } else {
      heroesError = value;
    }
  }

  void _setArt(_SgdbKind kind, List<ArtCandidate> value) {
    if (kind == _SgdbKind.grids) {
      grids = value;
    } else {
      heroes = value;
    }
  }

  void _setLoadedFor(_SgdbKind kind, String value) {
    if (kind == _SgdbKind.grids) {
      gridsFor = value;
    } else {
      heroesFor = value;
    }
  }

  /// Which lookup plus search selection a kind's art belongs to. Steam-ID art
  /// does not depend on the search selection; search art does.
  String _artKey(String print) {
    final ids = steamIds;
    if (ids != null && ids.isNotEmpty) return '$print|steam';
    return '$print|search:$selectedSearchId';
  }

  /// Loads [kind] unless it is already loaded for this lookup and selection.
  /// The Steam IDs and the name search come from the shared lookup: while the
  /// lookup is in flight a second caller joins it, and while this kind's
  /// fetch is in flight a second caller for this kind joins that instead, so
  /// a tab switch never repeats them.
  Future<void> ensureKind(
    _SgdbKind kind, {
    required Game game,
    required String key,
    required SteamGridDbClient? client,
    required VndbClient vndb,
  }) async {
    final print = fingerprint(game, key);
    if (client == null) return;
    final generation = _kindGeneration(kind);
    if (lookupFor == print && loadedFor(kind) == _artKey(print)) return;
    final joined = _kindFuture(kind);
    if (joined != null) {
      await joined;
      return;
    }
    if (lookupFor != print) {
      _setLoading(kind, true);
      _setError(kind, null);
      _notify();
      await _joinLookup(game: game, client: client, vndb: vndb, print: print);
      if (_fetchStale(kind, generation)) return;
      if (lookupFor != print) {
        _setLoading(kind, false);
        _setError(kind, _lookupError ?? 'network');
        _notify();
        return;
      }
    }
    if (loadedFor(kind) == _artKey(print)) {
      _setLoading(kind, false);
      _notify();
      return;
    }
    final pending = _kindFuture(kind);
    if (pending != null) {
      await pending;
      return;
    }
    if (_fetchStale(kind, generation)) return;
    _setLoading(kind, true);
    _setError(kind, null);
    _notify();
    final future = _fetchKindArt(kind, client, print, generation);
    _setKindFuture(kind, future);
    unawaited(
      future.whenComplete(() {
        if (identical(_kindFuture(kind), future)) _setKindFuture(kind, null);
      }),
    );
    await future;
  }

  /// Starts the shared lookup for [print], or joins it when one is already
  /// running for the same game and key.
  Future<void> _joinLookup({
    required Game game,
    required SteamGridDbClient client,
    required VndbClient vndb,
    required String print,
  }) {
    if (_lookupFuture != null && _lookupPrint == print) return _lookupFuture!;
    final generation = ++_lookupGeneration;
    _lookupError = null;
    final future = _runLookup(
      game: game,
      client: client,
      vndb: vndb,
      print: print,
      generation: generation,
    );
    _lookupFuture = future;
    _lookupPrint = print;
    unawaited(
      future.whenComplete(() {
        if (identical(_lookupFuture, future)) {
          _lookupFuture = null;
          _lookupPrint = '';
        }
      }),
    );
    return future;
  }

  Future<void> _runLookup({
    required Game game,
    required SteamGridDbClient client,
    required VndbClient vndb,
    required String print,
    required int generation,
  }) async {
    bool stale() => _disposed || generation != _lookupGeneration;
    try {
      List<int> ids = const [];
      if (game.launch.steamAppId != null) {
        ids = [game.launch.steamAppId!];
      } else if (game.vndbId != null) {
        try {
          ids = await vndb.fetchSteamAppIds(game.vndbId!);
        } catch (_) {
          ids = const [];
        }
      }
      if (stale()) return;
      if (ids.isNotEmpty) {
        steamIds = ids;
        search = null;
        lookupFor = print;
        _notify();
        return;
      }
      final results = await client.searchGames(game.title);
      if (stale()) return;
      final folded = normalizeGridTitle(game.title);
      int? selected;
      for (final result in results) {
        if (normalizeGridTitle(result.name) == folded) {
          selected = result.id;
          break;
        }
      }
      steamIds = const [];
      search = results;
      selectedSearchId = selected;
      lookupFor = print;
      _notify();
    } on SteamGridDbBadKeyException {
      if (stale()) return;
      _lookupError = 'badKey';
      _notify();
    } catch (_) {
      if (stale()) return;
      _lookupError = 'network';
      _notify();
    }
  }

  Future<void> _fetchKindArt(
    _SgdbKind kind,
    SteamGridDbClient client,
    String print,
    int generation,
  ) async {
    bool stale() => _fetchStale(kind, generation);
    try {
      final ids = steamIds;
      if (ids == null || ids.isEmpty) {
        final selected = selectedSearchId;
        if (selected == null) {
          _setArt(kind, const []);
          _setLoadedFor(kind, _artKey(print));
          _setLoading(kind, false);
          _notify();
          return;
        }
        final arts = await kind.fetchGame(client, selected);
        if (stale()) return;
        _setArt(kind, _dedupe(arts));
        _setLoadedFor(kind, _artKey(print));
        _setLoading(kind, false);
        _notify();
        return;
      }
      final merged = <ArtCandidate>[];
      final seen = <String>{};
      for (final id in ids) {
        final arts = await kind.fetchSteam(client, id);
        if (stale()) return;
        for (final art in arts) {
          if (seen.add(art.url)) merged.add(art);
        }
      }
      if (stale()) return;
      _setArt(kind, merged);
      _setLoadedFor(kind, _artKey(print));
      _setLoading(kind, false);
      _notify();
    } on SteamGridDbBadKeyException {
      if (stale()) return;
      _setLoading(kind, false);
      _setError(kind, 'badKey');
      _notify();
    } catch (_) {
      if (stale()) return;
      _setLoading(kind, false);
      _setError(kind, 'network');
      _notify();
    }
  }

  /// The user picked a search result: remember it for both tabs and load this
  /// tab's art for it. Only this kind's fetch is invalidated; the shared
  /// lookup and the other kind's fetch stand. The other tab follows on its
  /// next build.
  Future<void> selectSearch(
    _SgdbKind kind,
    int id, {
    required Game game,
    required String key,
    required SteamGridDbClient? client,
  }) async {
    if (client == null) return;
    final generation = kind == _SgdbKind.grids
        ? ++_gridsGeneration
        : ++_heroesGeneration;
    selectedSearchId = id;
    _setLoading(kind, true);
    _setError(kind, null);
    _notify();
    final future = _fetchKindArt(
      kind,
      client,
      fingerprint(game, key),
      generation,
    );
    _setKindFuture(kind, future);
    unawaited(
      future.whenComplete(() {
        if (identical(_kindFuture(kind), future)) _setKindFuture(kind, null);
      }),
    );
    await future;
  }

  List<ArtCandidate> _dedupe(List<ArtCandidate> arts) {
    final seen = <String>{};
    return [for (final art in arts) if (seen.add(art.url)) art];
  }
}

/// SteamGridDB art below the VNDB art: covers on the Cover tab, heroes on the
/// Background tab. Loads independently of VNDB so one source never blocks the
/// other. The lookup is shared between the tabs; only the key form is local.
class _SteamGridDbSection extends ConsumerStatefulWidget {
  const _SteamGridDbSection({
    super.key,
    required this.game,
    required this.kind,
    required this.shared,
    required this.selectedUrl,
    required this.isCurrent,
    required this.onPick,
  });

  final Game game;
  final _SgdbKind kind;
  final _SgdbShared shared;
  final String? selectedUrl;
  final bool Function(ArtCandidate) isCurrent;
  final void Function(ArtCandidate) onPick;

  @override
  ConsumerState<_SteamGridDbSection> createState() =>
      _SteamGridDbSectionState();
}

class _SteamGridDbSectionState extends ConsumerState<_SteamGridDbSection> {
  var _editingKey = false;
  late final TextEditingController _keyController;
  late final ProviderSubscription<String> _keySub;

  _SgdbShared get _shared => widget.shared;
  _SgdbKind get _kind => widget.kind;

  @override
  void initState() {
    super.initState();
    _keyController = TextEditingController();
    _keyController.addListener(() => setState(() {}));
    _shared.addListener(_onShared);
    _keySub = ref.listenManual<String>(steamGridDbKeyProvider, (
      previous,
      next,
    ) {
      if (!mounted) return;
      if ((previous ?? '').trim() == next.trim()) return;
      // A key saved from either tab resets the shared lookup and loads this
      // tab's art; the other tab follows from the shared lookup.
      _shared.reset();
      if (next.trim().isNotEmpty && !_editingKey) {
        unawaited(_load());
      }
    });
    if (ref.read(steamGridDbKeyProvider).trim().isNotEmpty) {
      Future.microtask(_load);
    }
  }

  @override
  void dispose() {
    _shared.removeListener(_onShared);
    _keySub.close();
    _keyController.dispose();
    super.dispose();
  }

  void _onShared() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(_SteamGridDbSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.game.id != widget.game.id) {
      _shared.reset();
      if (ref.read(steamGridDbKeyProvider).trim().isNotEmpty) {
        Future.microtask(_load);
      }
    }
  }

  Future<void> _load() => _shared.ensureKind(
    _kind,
    game: widget.game,
    key: ref.read(steamGridDbKeyProvider),
    client: ref.read(steamGridDbClientProvider),
    vndb: ref.read(vndbSearchClientProvider),
  );

  /// Retries the failed load. An art-fetch error retries only this kind's
  /// fetch, keeping the lookup, the search and the picked chip. A lookup
  /// error or a bad key redoes the lookup.
  Future<void> _retry() {
    final key = ref.read(steamGridDbKeyProvider);
    if (_shared.errorFor(_kind) != 'badKey' &&
        _shared.lookupFor == _SgdbShared.fingerprint(widget.game, key)) {
      return _load();
    }
    _shared.reset();
    return _load();
  }

  void _selectSearch(int id) {
    unawaited(
      _shared.selectSearch(
        _kind,
        id,
        game: widget.game,
        key: ref.read(steamGridDbKeyProvider),
        client: ref.read(steamGridDbClientProvider),
      ),
    );
  }

  void _saveKey() {
    final next = _keyController.text;
    final unchanged =
        ref.read(steamGridDbKeyProvider).trim() == next.trim() &&
        next.trim().isNotEmpty;
    _keyController.clear();
    setState(() => _editingKey = false);
    ref.read(steamGridDbKeyProvider.notifier).set(next);
    if (unchanged) {
      // Same key: the lookup still stands, so just reload this tab, which
      // retries a failed fetch or no-ops when it already loaded, instead of
      // repeating the lookup and dropping the picked search game.
      unawaited(_load());
    }
  }

  void _cancelKeyEdit() {
    _keyController.clear();
    setState(() => _editingKey = false);
    final key = ref.read(steamGridDbKeyProvider).trim();
    if (key.isNotEmpty &&
        _shared.lookupFor != _SgdbShared.fingerprint(widget.game, key) &&
        !_shared.lookupPending) {
      unawaited(_load());
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final key = ref.watch(steamGridDbKeyProvider);
    final hasKey = key.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'SteamGridDB',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (_artCount() != null)
                Text(
                  '${_artCount()}',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        if (_editingKey) _keyForm(scheme),
        if (!_editingKey && !hasKey) _noKeyNote(scheme),
        if (!_editingKey && hasKey) ..._keyedBody(scheme),
      ],
    );
  }

  int? _artCount() {
    final shared = _shared;
    if (shared.errorFor(_kind) != null ||
        shared.steamIds == null && shared.search == null) {
      return null;
    }
    if (shared.search != null && shared.selectedSearchId == null) return null;
    return shared.artFor(_kind).length;
  }

  Widget _noKeyNote(ColorScheme scheme) {
    return _DashedOutline(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _kind.noKeyMessage,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            BrandGlassButton(
              key: const Key('sgdb-set-key'),
              height: 40,
              expand: false,
              onPressed: () => setState(() => _editingKey = true),
              label: const Text('Set API key'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _keyForm(ColorScheme scheme) {
    return _DashedOutline(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('sgdb-key-field'),
              controller: _keyController,
              obscureText: true,
              decoration: InputDecoration(
                hintText: 'Paste your SteamGridDB API key',
                hintStyle: TextStyle(color: scheme.onSurfaceVariant),
                border: InputBorder.none,
                isDense: true,
              ),
              onSubmitted: (_) {
                if (_keyController.text.trim().isNotEmpty) _saveKey();
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton(
                  onPressed: () => ref
                      .read(vndbUrlOpenerProvider)(
                        Uri.parse(steamGridDbPreferencesUrl),
                      ),
                  child: const Text('Get a key'),
                ),
                const Spacer(),
                BrandGlassButton(
                  key: const Key('sgdb-key-cancel'),
                  height: 40,
                  expand: false,
                  onPressed: _cancelKeyEdit,
                  label: const Text('Cancel'),
                ),
                const SizedBox(width: 10),
                BrandButton(
                  key: const Key('sgdb-key-save'),
                  height: 40,
                  expand: false,
                  onPressed: _keyController.text.trim().isEmpty
                      ? null
                      : _saveKey,
                  label: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _keyedBody(ColorScheme scheme) {
    final shared = _shared;
    final arts = shared.artFor(_kind);
    final loading = shared.loadingFor(_kind);
    final selectedSearchId = shared.selectedSearchId;
    final emptyMessage = _kind.emptyMessage;
    if (shared.errorFor(_kind) == 'badKey') {
      return [
        const Text("SteamGridDB didn't accept the key."),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: BrandGlassButton(
            key: const Key('sgdb-set-key'),
            height: 40,
            expand: false,
            onPressed: () => setState(() => _editingKey = true),
            label: const Text('Set API key'),
          ),
        ),
      ];
    }
    if (shared.errorFor(_kind) != null) {
      return [
        const Text("Couldn't reach SteamGridDB."),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: BrandGlassButton(
            key: const Key('sgdb-retry'),
            height: 40,
            expand: false,
            onPressed: _retry,
            label: const Text('Try again'),
          ),
        ),
      ];
    }
    if (shared.steamIds == null && shared.search == null) {
      return const [_SgdbPending()];
    }
    if (shared.steamIds != null && shared.steamIds!.isNotEmpty) {
      if (arts.isNotEmpty) return [_grid(scheme, arts)];
      if (loading) return const [_SgdbPending()];
      return [Text(emptyMessage)];
    }
    final search = shared.search ?? const <SteamGridDbGame>[];
    if (search.isEmpty) {
      return [Text(emptyMessage)];
    }
    return [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final result in search) _chip(scheme, result),
        ],
      ),
      const SizedBox(height: 10),
      if (selectedSearchId == null)
        const Text('Pick the matching game.')
      else if (!loading && arts.isEmpty)
        Text(emptyMessage)
      else
        _grid(scheme, arts),
      if (loading && selectedSearchId != null && arts.isEmpty)
        const _SgdbPending(),
    ];
  }

  Widget _chip(ColorScheme scheme, SteamGridDbGame result) {
    final selected = result.id == _shared.selectedSearchId;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _selectSearch(result.id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Text(
          result.name,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _grid(ColorScheme scheme, List<ArtCandidate> arts) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 14.0;
        final columnWidth =
            (constraints.maxWidth - spacing * (_kind.columns - 1)) /
            _kind.columns;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: _kind.columns,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            mainAxisExtent:
                columnWidth / _kind.aspectRatio + _kArtCaptionExtent,
          ),
          itemCount: arts.length,
          itemBuilder: (context, index) {
            final art = arts[index];
            return _ArtTile(
              key: ValueKey('art-${art.url}'),
              art: art,
              aspectRatio: _kind.aspectRatio,
              selected: widget.selectedUrl == art.url,
              current: widget.isCurrent(art),
              onTap: () => widget.onPick(art),
            );
          },
        );
      },
    );
  }
}

/// Small loading mark while a SteamGridDB lookup or art fetch is pending.
class _SgdbPending extends StatelessWidget {
  const _SgdbPending();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TsumigeLogoShimmer(size: 32),
      ),
    );
  }
}

/// Dashed rounded outline for the SteamGridDB key note and key form.
class _DashedOutline extends StatelessWidget {
  const _DashedOutline({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CustomPaint(
      painter: _DashPainter(scheme.outlineVariant),
      child: child,
    );
  }
}

class _DashPainter extends CustomPainter {
  _DashPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(10),
        ),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    const dash = 6.0;
    const gap = 4.0;
    for (final metric in path.computeMetrics()) {
      var start = 0.0;
      while (start < metric.length) {
        final end = (start + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(start, end), paint);
        start += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashPainter old) => old.color != color;
}

/// Room under each picker image for its size caption: the gap plus one line.
const double _kArtCaptionExtent = 18;

/// One VNDB image in a picker grid, with the grid ring and its size below.
class _ArtTile extends StatefulWidget {
  const _ArtTile({
    super.key,
    required this.art,
    required this.aspectRatio,
    required this.selected,
    required this.current,
    required this.onTap,
  });

  final ArtCandidate art;
  final double aspectRatio;
  final bool selected;
  final bool current;
  final VoidCallback onTap;

  @override
  State<_ArtTile> createState() => _ArtTileState();
}

class _ArtTileState extends State<_ArtTile> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final art = widget.art;
    const radius = BorderRadius.all(Radius.circular(10));
    final lit = widget.selected || _hovered;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: widget.aspectRatio,
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: radius,
                ),
                foregroundDecoration: BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(
                    color: lit
                        ? scheme.primary
                        : scheme.onSurface.withValues(alpha: 0.06),
                    width: widget.selected ? 3 : (_hovered ? 2 : 1),
                  ),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      art.thumbnail,
                      fit: BoxFit.contain,
                      alignment: Alignment.center,
                      loadingBuilder: (context, child, progress) =>
                          progress == null
                          ? child
                          : const SizedBox.shrink(),
                      errorBuilder: (_, _, _) => Center(
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (widget.current)
                      Positioned(
                        left: 6,
                        top: 6,
                        child: Container(
                          height: 22,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: ArtOverlay.button,
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(color: ArtOverlay.buttonRing),
                          ),
                          child: const Text(
                            'Current',
                            style: TextStyle(
                              fontSize: 11,
                              color: OnImage.text,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 14,
              child: Text(
                art.width > 0 && art.height > 0
                    ? '${art.width}×${art.height}'
                    : '',
                maxLines: 1,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
