// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'add_game.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// HTTP client for VNDB search and cover downloads. Tests override this with
/// a MockClient so the real VNDB API is never called.

@ProviderFor(addGameHttpClient)
final addGameHttpClientProvider = AddGameHttpClientProvider._();

/// HTTP client for VNDB search and cover downloads. Tests override this with
/// a MockClient so the real VNDB API is never called.

final class AddGameHttpClientProvider
    extends $FunctionalProvider<http.Client, http.Client, http.Client>
    with $Provider<http.Client> {
  /// HTTP client for VNDB search and cover downloads. Tests override this with
  /// a MockClient so the real VNDB API is never called.
  AddGameHttpClientProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'addGameHttpClientProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$addGameHttpClientHash();

  @$internal
  @override
  $ProviderElement<http.Client> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  http.Client create(Ref ref) {
    return addGameHttpClient(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(http.Client value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<http.Client>(value),
    );
  }
}

String _$addGameHttpClientHash() => r'a818d8a249be9e63da8ca051fb709d3082404f24';

/// VNDB client built on the overridable HTTP client above.

@ProviderFor(vndbSearchClient)
final vndbSearchClientProvider = VndbSearchClientProvider._();

/// VNDB client built on the overridable HTTP client above.

final class VndbSearchClientProvider
    extends $FunctionalProvider<VndbClient, VndbClient, VndbClient>
    with $Provider<VndbClient> {
  /// VNDB client built on the overridable HTTP client above.
  VndbSearchClientProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'vndbSearchClientProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$vndbSearchClientHash();

  @$internal
  @override
  $ProviderElement<VndbClient> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  VndbClient create(Ref ref) {
    return vndbSearchClient(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(VndbClient value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<VndbClient>(value),
    );
  }
}

String _$vndbSearchClientHash() => r'5879c759bb4cb7e7811e8c14e68623e4957a6ebf';
