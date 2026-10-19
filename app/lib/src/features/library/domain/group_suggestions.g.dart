// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'group_suggestions.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Episode-group suggestions the user hasn't marked "Not a series".

@ProviderFor(groupSuggestions)
final groupSuggestionsProvider = GroupSuggestionsProvider._();

/// Episode-group suggestions the user hasn't marked "Not a series".

final class GroupSuggestionsProvider
    extends
        $FunctionalProvider<
          List<GroupSuggestion>,
          List<GroupSuggestion>,
          List<GroupSuggestion>
        >
    with $Provider<List<GroupSuggestion>> {
  /// Episode-group suggestions the user hasn't marked "Not a series".
  GroupSuggestionsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'groupSuggestionsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$groupSuggestionsHash();

  @$internal
  @override
  $ProviderElement<List<GroupSuggestion>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  List<GroupSuggestion> create(Ref ref) {
    return groupSuggestions(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<GroupSuggestion> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<GroupSuggestion>>(value),
    );
  }
}

String _$groupSuggestionsHash() => r'457b5c4db3f0249950b0055aa2a91c351f747114';

/// The suggestions the notice shows: none while the current suggestion keys
/// equal the keys the notice was last dismissed with. Any change — a new
/// suggestable game, a grouping, a "Not a series" — shows it again.

@ProviderFor(visibleGroupSuggestions)
final visibleGroupSuggestionsProvider = VisibleGroupSuggestionsProvider._();

/// The suggestions the notice shows: none while the current suggestion keys
/// equal the keys the notice was last dismissed with. Any change — a new
/// suggestable game, a grouping, a "Not a series" — shows it again.

final class VisibleGroupSuggestionsProvider
    extends
        $FunctionalProvider<
          List<GroupSuggestion>,
          List<GroupSuggestion>,
          List<GroupSuggestion>
        >
    with $Provider<List<GroupSuggestion>> {
  /// The suggestions the notice shows: none while the current suggestion keys
  /// equal the keys the notice was last dismissed with. Any change — a new
  /// suggestable game, a grouping, a "Not a series" — shows it again.
  VisibleGroupSuggestionsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'visibleGroupSuggestionsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$visibleGroupSuggestionsHash();

  @$internal
  @override
  $ProviderElement<List<GroupSuggestion>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  List<GroupSuggestion> create(Ref ref) {
    return visibleGroupSuggestions(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<GroupSuggestion> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<GroupSuggestion>>(value),
    );
  }
}

String _$visibleGroupSuggestionsHash() =>
    r'd8cb725c0617d26cf35d228b26512d0460178621';
