// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../../../core/vndb.dart';
import '../../domain/vndb_markup.dart';

class VnResultRow extends StatelessWidget {
  const VnResultRow({
    super.key,
    required this.result,
    required this.owned,
    this.onPick,
    this.current = false,
    this.selected = false,
    this.badge,
  });

  final VnSearchResult result;
  final bool owned;
  final VoidCallback? onPick;
  final bool current;

  /// A label shown in place of "Current match", for a row that isn't the
  /// current pick.
  final String? badge;

  /// Draws the selection ring without the current-match label.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(
      fontSize: 13,
      color: scheme.onSurfaceVariant,
    );
    final year = vnYear(result.released);
    final meta = [
      if (year.isNotEmpty) year,
      if (result.developers.isNotEmpty) result.developers.join(', '),
    ].join(' · ');
    final rating = result.rating == null
        ? null
        : '★ ${(result.rating! / 10).toStringAsFixed(1)}';
    final alt = result.alttitle;
    final row = InkWell(
      borderRadius: BorderRadius.circular(12),
      hoverColor: scheme.onSurface.withValues(alpha: 0.04),
      onTap: onPick,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            VnCoverThumb(
              imageUrl: result.imageUrl,
              sexual: result.imageSexual,
              width: 54,
              height: 72,
              radius: 8,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Opacity(
                opacity: owned ? 0.55 : 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (alt != null && alt.isNotEmpty) Text(alt, style: muted),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            meta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: muted,
                          ),
                        ),
                        if (rating != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            rating,
                            style: muted?.copyWith(color: scheme.primary),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (owned || current || badge != null) ...[
              const SizedBox(width: 10),
              Container(
                height: 24,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: owned
                      ? scheme.primaryContainer
                      : scheme.onSurface.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  owned ? 'In library' : (badge ?? 'Current match'),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: owned ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
    if (!current && !selected) return row;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.primary, width: 2),
      ),
      child: row,
    );
  }
}

/// The selected VNDB result: a large cover and its main facts.
class VnDetailPanel extends StatelessWidget {
  const VnDetailPanel({super.key, required this.result});

  final VnSearchResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final alt = result.alttitle;
    final year = vnYear(result.released);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Selected',
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        VnCoverThumb(
          imageUrl: result.imageUrl,
          sexual: result.imageSexual,
          width: 180,
          height: 240,
          radius: 10,
        ),
        const SizedBox(height: 12),
        Text(
          result.title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        if (alt != null && alt.isNotEmpty) Text(alt, style: muted),
        const SizedBox(height: 10),
        if (result.developers.isNotEmpty)
          _Fact(
            label: 'Developer',
            value: result.developers.join(', '),
          ),
        if (year.isNotEmpty) _Fact(label: 'Released', value: year),
        if (result.description.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            vndbPlainText(result.description),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: muted,
          ),
        ],
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          Text(value, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}

String vnYear(String? released) {
  if (released == null || released.isEmpty) return '';
  final match = RegExp(r'^\d{4}').firstMatch(released);
  return match?.group(0) ?? released;
}

class VnCoverThumb extends StatelessWidget {
  const VnCoverThumb({
    super.key,
    required this.imageUrl,
    required this.sexual,
    required this.width,
    required this.height,
    required this.radius,
  });

  final String? imageUrl;
  final int sexual;
  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    if (url == null || url.isEmpty) {
      final scheme = Theme.of(context).colorScheme;
      return Container(
        width: width,
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Icon(
          Icons.image_not_supported_outlined,
          color: scheme.onSurfaceVariant,
        ),
      );
    }
    Widget art = Image.network(
      url,
      width: width,
      height: height,
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
    return SizedBox(
      width: width,
      height: height,
      child: ClipRRect(borderRadius: BorderRadius.circular(radius), child: art),
    );
  }
}
