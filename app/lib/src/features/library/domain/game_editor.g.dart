// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'game_editor.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Every pane edit saves through here: apply [change] to the game with
/// [gameId], then save. The id is captured when the edit starts, never the
/// currently selected game, so a blur-save after switching games still lands
/// on the original game.

@ProviderFor(gameEditor)
final gameEditorProvider = GameEditorProvider._();

/// Every pane edit saves through here: apply [change] to the game with
/// [gameId], then save. The id is captured when the edit starts, never the
/// currently selected game, so a blur-save after switching games still lands
/// on the original game.

final class GameEditorProvider
    extends $FunctionalProvider<GameEditor, GameEditor, GameEditor>
    with $Provider<GameEditor> {
  /// Every pane edit saves through here: apply [change] to the game with
  /// [gameId], then save. The id is captured when the edit starts, never the
  /// currently selected game, so a blur-save after switching games still lands
  /// on the original game.
  GameEditorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'gameEditorProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$gameEditorHash();

  @$internal
  @override
  $ProviderElement<GameEditor> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  GameEditor create(Ref ref) {
    return gameEditor(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(GameEditor value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<GameEditor>(value),
    );
  }
}

String _$gameEditorHash() => r'3cf1399bb0fd828355ea14083ae33303789795c4';

/// Cover picker seam: tests override this so no real dialog ever opens.

@ProviderFor(coverPicker)
final coverPickerProvider = CoverPickerProvider._();

/// Cover picker seam: tests override this so no real dialog ever opens.

final class CoverPickerProvider
    extends
        $FunctionalProvider<
          Future<String?> Function(),
          Future<String?> Function(),
          Future<String?> Function()
        >
    with $Provider<Future<String?> Function()> {
  /// Cover picker seam: tests override this so no real dialog ever opens.
  CoverPickerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'coverPickerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$coverPickerHash();

  @$internal
  @override
  $ProviderElement<Future<String?> Function()> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  Future<String?> Function() create(Ref ref) {
    return coverPicker(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Future<String?> Function() value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Future<String?> Function()>(value),
    );
  }
}

String _$coverPickerHash() => r'657d67780161eae818a05fa54aa7d934f8693f65';

/// Path picker seam: tests override this so no real dialog ever opens.

@ProviderFor(pathPicker)
final pathPickerProvider = PathPickerProvider._();

/// Path picker seam: tests override this so no real dialog ever opens.

final class PathPickerProvider
    extends
        $FunctionalProvider<
          Future<String?> Function({
            String? initialDirectory,
            PathPickMode mode,
          }),
          Future<String?> Function({
            String? initialDirectory,
            PathPickMode mode,
          }),
          Future<String?> Function({
            String? initialDirectory,
            PathPickMode mode,
          })
        >
    with
        $Provider<
          Future<String?> Function({
            String? initialDirectory,
            PathPickMode mode,
          })
        > {
  /// Path picker seam: tests override this so no real dialog ever opens.
  PathPickerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'pathPickerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$pathPickerHash();

  @$internal
  @override
  $ProviderElement<
    Future<String?> Function({String? initialDirectory, PathPickMode mode})
  >
  $createElement($ProviderPointer pointer) => $ProviderElement(pointer);

  @override
  Future<String?> Function({String? initialDirectory, PathPickMode mode})
  create(Ref ref) {
    return pathPicker(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(
    Future<String?> Function({String? initialDirectory, PathPickMode mode})
    value,
  ) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<
            Future<String?> Function({
              String? initialDirectory,
              PathPickMode mode,
            })
          >(value),
    );
  }
}

String _$pathPickerHash() => r'dbb130a1f53b29b6b8ed5a791327286ec8457ae3';
