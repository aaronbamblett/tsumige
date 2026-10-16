// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_prefs.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Cover grid tile width in logical pixels, clamped to 100..999.

@ProviderFor(CoverWidth)
final coverWidthProvider = CoverWidthProvider._();

/// Cover grid tile width in logical pixels, clamped to 100..999.
final class CoverWidthProvider extends $NotifierProvider<CoverWidth, int> {
  /// Cover grid tile width in logical pixels, clamped to 100..999.
  CoverWidthProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'coverWidthProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$coverWidthHash();

  @$internal
  @override
  CoverWidth create() => CoverWidth();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int>(value),
    );
  }
}

String _$coverWidthHash() => r'8bda59ad9e39969548a9ccb92a65b7f0e620e381';

/// Cover grid tile width in logical pixels, clamped to 100..999.

abstract class _$CoverWidth extends $Notifier<int> {
  int build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<int, int>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<int, int>,
              int,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Library sort order. Stored as the enum index; out-of-range reads fall back
/// to [keys.SortField.added].

@ProviderFor(SortField)
final sortFieldProvider = SortFieldProvider._();

/// Library sort order. Stored as the enum index; out-of-range reads fall back
/// to [keys.SortField.added].
final class SortFieldProvider
    extends $NotifierProvider<SortField, keys.SortField> {
  /// Library sort order. Stored as the enum index; out-of-range reads fall back
  /// to [keys.SortField.added].
  SortFieldProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sortFieldProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sortFieldHash();

  @$internal
  @override
  SortField create() => SortField();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(keys.SortField value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<keys.SortField>(value),
    );
  }
}

String _$sortFieldHash() => r'd5df6d2c5e19f6934b5cf31ac645e734910acd0d';

/// Library sort order. Stored as the enum index; out-of-range reads fall back
/// to [keys.SortField.added].

abstract class _$SortField extends $Notifier<keys.SortField> {
  keys.SortField build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<keys.SortField, keys.SortField>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<keys.SortField, keys.SortField>,
              keys.SortField,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// False sorts descending.

@ProviderFor(SortAscending)
final sortAscendingProvider = SortAscendingProvider._();

/// False sorts descending.
final class SortAscendingProvider
    extends $NotifierProvider<SortAscending, bool> {
  /// False sorts descending.
  SortAscendingProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sortAscendingProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sortAscendingHash();

  @$internal
  @override
  SortAscending create() => SortAscending();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$sortAscendingHash() => r'a04312eb0a6b5cda524a9f2155a1b79c4a2c2ea3';

/// False sorts descending.

abstract class _$SortAscending extends $Notifier<bool> {
  bool build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(FavouritesOnly)
final favouritesOnlyProvider = FavouritesOnlyProvider._();

final class FavouritesOnlyProvider
    extends $NotifierProvider<FavouritesOnly, bool> {
  FavouritesOnlyProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'favouritesOnlyProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$favouritesOnlyHash();

  @$internal
  @override
  FavouritesOnly create() => FavouritesOnly();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$favouritesOnlyHash() => r'180acb92a021fb52411791937b4afc0d1afb5e7f';

abstract class _$FavouritesOnly extends $Notifier<bool> {
  bool build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Tag filter; null means no filter.

@ProviderFor(TagFilter)
final tagFilterProvider = TagFilterProvider._();

/// Tag filter; null means no filter.
final class TagFilterProvider extends $NotifierProvider<TagFilter, String?> {
  /// Tag filter; null means no filter.
  TagFilterProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'tagFilterProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$tagFilterHash();

  @$internal
  @override
  TagFilter create() => TagFilter();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String?>(value),
    );
  }
}

String _$tagFilterHash() => r'75e0390e8154bea090d7b13f7234fc456dbb32bf';

/// Tag filter; null means no filter.

abstract class _$TagFilter extends $Notifier<String?> {
  String? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<String?, String?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<String?, String?>,
              String?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
