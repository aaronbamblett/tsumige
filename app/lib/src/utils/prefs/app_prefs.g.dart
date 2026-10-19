// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_prefs.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Cover grid tile width in logical pixels, clamped to 100..400.

@ProviderFor(CoverWidth)
final coverWidthProvider = CoverWidthProvider._();

/// Cover grid tile width in logical pixels, clamped to 100..400.
final class CoverWidthProvider extends $NotifierProvider<CoverWidth, int> {
  /// Cover grid tile width in logical pixels, clamped to 100..400.
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

/// Cover grid tile width in logical pixels, clamped to 100..400.

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

/// Adult filter; stored as the enum index, out-of-range reads fall back to
/// [keys.AdultFilter.all].

@ProviderFor(AdultFilter)
final adultFilterProvider = AdultFilterProvider._();

/// Adult filter; stored as the enum index, out-of-range reads fall back to
/// [keys.AdultFilter.all].
final class AdultFilterProvider
    extends $NotifierProvider<AdultFilter, keys.AdultFilter> {
  /// Adult filter; stored as the enum index, out-of-range reads fall back to
  /// [keys.AdultFilter.all].
  AdultFilterProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'adultFilterProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$adultFilterHash();

  @$internal
  @override
  AdultFilter create() => AdultFilter();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(keys.AdultFilter value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<keys.AdultFilter>(value),
    );
  }
}

String _$adultFilterHash() => r'c8d997f5e490a8a40886af14624fad610499440c';

/// Adult filter; stored as the enum index, out-of-range reads fall back to
/// [keys.AdultFilter.all].

abstract class _$AdultFilter extends $Notifier<keys.AdultFilter> {
  keys.AdultFilter build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<keys.AdultFilter, keys.AdultFilter>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<keys.AdultFilter, keys.AdultFilter>,
              keys.AdultFilter,
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

/// Default Wine/Proton prefix for games. Nothing reads it yet.

@ProviderFor(LaunchPrefix)
final launchPrefixProvider = LaunchPrefixProvider._();

/// Default Wine/Proton prefix for games. Nothing reads it yet.
final class LaunchPrefixProvider
    extends $NotifierProvider<LaunchPrefix, String> {
  /// Default Wine/Proton prefix for games. Nothing reads it yet.
  LaunchPrefixProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'launchPrefixProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$launchPrefixHash();

  @$internal
  @override
  LaunchPrefix create() => LaunchPrefix();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String>(value),
    );
  }
}

String _$launchPrefixHash() => r'8a7c03e64dbd282e1108a1c02e83cd58cdb6de30';

/// Default Wine/Proton prefix for games. Nothing reads it yet.

abstract class _$LaunchPrefix extends $Notifier<String> {
  String build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<String, String>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<String, String>,
              String,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Default runner override; null means umu's default. Nothing reads it yet.

@ProviderFor(LaunchRunner)
final launchRunnerProvider = LaunchRunnerProvider._();

/// Default runner override; null means umu's default. Nothing reads it yet.
final class LaunchRunnerProvider
    extends $NotifierProvider<LaunchRunner, String?> {
  /// Default runner override; null means umu's default. Nothing reads it yet.
  LaunchRunnerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'launchRunnerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$launchRunnerHash();

  @$internal
  @override
  LaunchRunner create() => LaunchRunner();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String?>(value),
    );
  }
}

String _$launchRunnerHash() => r'55cec9eef11589afbac25570a8c52ba6e4002c92';

/// Default runner override; null means umu's default. Nothing reads it yet.

abstract class _$LaunchRunner extends $Notifier<String?> {
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

/// Default locale for launched games. Nothing reads it yet.

@ProviderFor(LaunchLocale)
final launchLocaleProvider = LaunchLocaleProvider._();

/// Default locale for launched games. Nothing reads it yet.
final class LaunchLocaleProvider
    extends $NotifierProvider<LaunchLocale, String> {
  /// Default locale for launched games. Nothing reads it yet.
  LaunchLocaleProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'launchLocaleProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$launchLocaleHash();

  @$internal
  @override
  LaunchLocale create() => LaunchLocale();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String>(value),
    );
  }
}

String _$launchLocaleHash() => r'2a5a3e48beb99e36da04a33c1745211cd040b5fa';

/// Default locale for launched games. Nothing reads it yet.

abstract class _$LaunchLocale extends $Notifier<String> {
  String build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<String, String>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<String, String>,
              String,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Default UMU game id for launched games. Nothing reads it yet.

@ProviderFor(LaunchUmuGameId)
final launchUmuGameIdProvider = LaunchUmuGameIdProvider._();

/// Default UMU game id for launched games. Nothing reads it yet.
final class LaunchUmuGameIdProvider
    extends $NotifierProvider<LaunchUmuGameId, String> {
  /// Default UMU game id for launched games. Nothing reads it yet.
  LaunchUmuGameIdProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'launchUmuGameIdProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$launchUmuGameIdHash();

  @$internal
  @override
  LaunchUmuGameId create() => LaunchUmuGameId();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String>(value),
    );
  }
}

String _$launchUmuGameIdHash() => r'97d5d0fad52354fdbcecc674b3dc0a327adb9234';

/// Default UMU game id for launched games. Nothing reads it yet.

abstract class _$LaunchUmuGameId extends $Notifier<String> {
  String build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<String, String>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<String, String>,
              String,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// SteamGridDB API key, user-supplied. Empty means the source is off.

@ProviderFor(SteamGridDbKey)
final steamGridDbKeyProvider = SteamGridDbKeyProvider._();

/// SteamGridDB API key, user-supplied. Empty means the source is off.
final class SteamGridDbKeyProvider
    extends $NotifierProvider<SteamGridDbKey, String> {
  /// SteamGridDB API key, user-supplied. Empty means the source is off.
  SteamGridDbKeyProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'steamGridDbKeyProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$steamGridDbKeyHash();

  @$internal
  @override
  SteamGridDbKey create() => SteamGridDbKey();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String>(value),
    );
  }
}

String _$steamGridDbKeyHash() => r'18684dedf18e948deca7b701a74a8558b1cbffd4';

/// SteamGridDB API key, user-supplied. Empty means the source is off.

abstract class _$SteamGridDbKey extends $Notifier<String> {
  String build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<String, String>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<String, String>,
              String,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Info tab sections shown on the details panel. Stored as a string list, a
/// missing key or any unknown entry means every field is shown.

@ProviderFor(DetailFields)
final detailFieldsProvider = DetailFieldsProvider._();

/// Info tab sections shown on the details panel. Stored as a string list, a
/// missing key or any unknown entry means every field is shown.
final class DetailFieldsProvider
    extends $NotifierProvider<DetailFields, Set<String>> {
  /// Info tab sections shown on the details panel. Stored as a string list, a
  /// missing key or any unknown entry means every field is shown.
  DetailFieldsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'detailFieldsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$detailFieldsHash();

  @$internal
  @override
  DetailFields create() => DetailFields();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Set<String> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Set<String>>(value),
    );
  }
}

String _$detailFieldsHash() => r'307d6bc5a0bdbb75b63efa8bc83960b14a773a78';

/// Info tab sections shown on the details panel. Stored as a string list, a
/// missing key or any unknown entry means every field is shown.

abstract class _$DetailFields extends $Notifier<Set<String>> {
  Set<String> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<Set<String>, Set<String>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Set<String>, Set<String>>,
              Set<String>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Suggestion keys the grouping notice was dismissed with. The notice hides
/// while the current suggestion keys equal these; any change shows it again.
/// Stored as a string list; a missing key means it was never dismissed.

@ProviderFor(DismissedSuggestionNotice)
final dismissedSuggestionNoticeProvider = DismissedSuggestionNoticeProvider._();

/// Suggestion keys the grouping notice was dismissed with. The notice hides
/// while the current suggestion keys equal these; any change shows it again.
/// Stored as a string list; a missing key means it was never dismissed.
final class DismissedSuggestionNoticeProvider
    extends $NotifierProvider<DismissedSuggestionNotice, Set<String>> {
  /// Suggestion keys the grouping notice was dismissed with. The notice hides
  /// while the current suggestion keys equal these; any change shows it again.
  /// Stored as a string list; a missing key means it was never dismissed.
  DismissedSuggestionNoticeProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'dismissedSuggestionNoticeProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$dismissedSuggestionNoticeHash();

  @$internal
  @override
  DismissedSuggestionNotice create() => DismissedSuggestionNotice();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Set<String> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Set<String>>(value),
    );
  }
}

String _$dismissedSuggestionNoticeHash() =>
    r'ce78dc8a2519f26ece9856df7cc1496cc4a75fe4';

/// Suggestion keys the grouping notice was dismissed with. The notice hides
/// while the current suggestion keys equal these; any change shows it again.
/// Stored as a string list; a missing key means it was never dismissed.

abstract class _$DismissedSuggestionNotice extends $Notifier<Set<String>> {
  Set<String> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<Set<String>, Set<String>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Set<String>, Set<String>>,
              Set<String>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
