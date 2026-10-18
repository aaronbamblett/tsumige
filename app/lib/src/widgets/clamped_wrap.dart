// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// A [Wrap]-like layout that shows only the leading children fitting in
/// [maxRows] rows, with an optional [trailing] child pinned after them.
///
/// Children are laid out start-aligned with [spacing] between them and
/// [runSpacing] between rows. Every child is laid out, so the fold is
/// measured from the real sizes. With [maxRows] set, only the leading
/// children that fit are painted and hit-tested; [trailing], when set, is
/// always shown last inside the row limit, dropping further leading children
/// as needed. The height sizes to the shown rows only. A null [maxRows] lays
/// out everything, like a normal [Wrap].
///
/// [onOverflowChanged] reports whether any leading child was dropped. It runs
/// in a post-frame callback, and only when the value changes.
class ClampedWrap extends MultiChildRenderObjectWidget {
  ClampedWrap({
    super.key,
    this.spacing = 0.0,
    this.runSpacing = 0.0,
    this.maxRows,
    this.crossAxisAlignment = WrapCrossAlignment.start,
    this.onOverflowChanged,
    List<Widget> children = const <Widget>[],
    Widget? trailing,
  })  : _trailing = trailing,
        super(
            children: trailing == null
                ? children
                : <Widget>[...children, trailing]);

  final double spacing;
  final double runSpacing;
  final int? maxRows;
  final WrapCrossAlignment crossAxisAlignment;
  final ValueChanged<bool>? onOverflowChanged;
  final Widget? _trailing;

  int get _leadingCount =>
      children.length - (_trailing == null ? 0 : 1);

  @override
  MultiChildRenderObjectElement createElement() => _ClampedWrapElement(this);

  @override
  RenderClampedWrap createRenderObject(BuildContext context) {
    return RenderClampedWrap(
      spacing: spacing,
      runSpacing: runSpacing,
      maxRows: maxRows,
      crossAxisAlignment: crossAxisAlignment,
      textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
      leadingCount: _leadingCount,
      onOverflowChanged: onOverflowChanged,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderClampedWrap renderObject) {
    renderObject
      ..spacing = spacing
      ..runSpacing = runSpacing
      ..maxRows = maxRows
      ..crossAxisAlignment = crossAxisAlignment
      ..textDirection = Directionality.maybeOf(context) ?? TextDirection.ltr
      ..leadingCount = _leadingCount
      ..onOverflowChanged = onOverflowChanged;
  }
}

/// Element for [ClampedWrap]. Hidden children are offstage: default test
/// finders and the inspector skip them, like [IndexedStack] does.
class _ClampedWrapElement extends MultiChildRenderObjectElement {
  _ClampedWrapElement(ClampedWrap super.widget);

  @override
  void debugVisitOnstageChildren(ElementVisitor visitor) {
    final render = renderObject as RenderClampedWrap;
    var index = 0;
    visitChildren((Element child) {
      if (index < render.visibleLeadingCount ||
          index >= render.leadingCount) {
        visitor(child);
      }
      index++;
    });
  }
}

/// Parent data for [RenderClampedWrap].
class ClampedWrapParentData extends ContainerBoxParentData<RenderBox> {}

/// The [RenderBox] behind [ClampedWrap]. Kept public so tests can read the
/// measured fold ([visibleLeadingCount], [overflowed]).
class RenderClampedWrap extends RenderBox
    with ContainerRenderObjectMixin<RenderBox, ClampedWrapParentData> {
  RenderClampedWrap({
    double spacing = 0.0,
    double runSpacing = 0.0,
    int? maxRows,
    WrapCrossAlignment crossAxisAlignment = WrapCrossAlignment.start,
    TextDirection textDirection = TextDirection.ltr,
    int leadingCount = 0,
    this.onOverflowChanged,
  }) {
    assert(maxRows == null || maxRows > 0);
    _spacing = spacing;
    _runSpacing = runSpacing;
    _maxRows = maxRows;
    _crossAxisAlignment = crossAxisAlignment;
    _textDirection = textDirection;
    _leadingCount = leadingCount;
  }

  double get spacing => _spacing;
  double _spacing = 0.0;
  set spacing(double value) {
    if (value == _spacing) return;
    _spacing = value;
    markNeedsLayout();
  }

  double get runSpacing => _runSpacing;
  double _runSpacing = 0.0;
  set runSpacing(double value) {
    if (value == _runSpacing) return;
    _runSpacing = value;
    markNeedsLayout();
  }

  int? get maxRows => _maxRows;
  int? _maxRows;
  set maxRows(int? value) {
    assert(value == null || value > 0);
    if (value == _maxRows) return;
    _maxRows = value;
    markNeedsLayout();
  }

  WrapCrossAlignment get crossAxisAlignment => _crossAxisAlignment;
  WrapCrossAlignment _crossAxisAlignment = WrapCrossAlignment.start;
  set crossAxisAlignment(WrapCrossAlignment value) {
    if (value == _crossAxisAlignment) return;
    _crossAxisAlignment = value;
    markNeedsLayout();
  }

  TextDirection get textDirection => _textDirection;
  TextDirection _textDirection = TextDirection.ltr;
  set textDirection(TextDirection value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsLayout();
  }

  int get leadingCount => _leadingCount;
  int _leadingCount = 0;
  set leadingCount(int value) {
    if (value == _leadingCount) return;
    _leadingCount = value;
    markNeedsLayout();
  }

  ValueChanged<bool>? onOverflowChanged;

  /// Leading children currently painted and hit-tested.
  int get visibleLeadingCount => _visibleLeading;
  int _visibleLeading = 0;

  /// Whether any leading child is currently dropped.
  bool get overflowed => _overflow;
  bool _overflow = false;
  bool _notified = false;
  bool _notifyScheduled = false;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! ClampedWrapParentData) {
      child.parentData = ClampedWrapParentData();
    }
  }

  int _rowsFor(List<double> widths, double limit) {
    if (widths.isEmpty) return 0;
    var rows = 1;
    var x = widths.first;
    for (var i = 1; i < widths.length; i++) {
      final w = widths[i];
      if (x + _spacing + w <= limit + 1e-9) {
        x += _spacing + w;
      } else {
        rows++;
        x = w;
      }
    }
    return rows;
  }

  @override
  void performLayout() {
    final boxes = <RenderBox>[];
    RenderBox? child = firstChild;
    while (child != null) {
      boxes.add(child);
      final next = childAfter(child);
      child = next;
    }
    final rawLimit = constraints.maxWidth;
    final limit = rawLimit.isFinite ? rawLimit : double.infinity;
    for (final box in boxes) {
      box.layout(BoxConstraints(maxWidth: limit), parentUsesSize: true);
    }
    final widths = <double>[for (final box in boxes) box.size.width];

    final leading = _leadingCount.clamp(0, boxes.length).toInt();
    final hasTrailing = boxes.length > leading;
    final maxRows = _maxRows;
    List<int> shown;
    if (maxRows == null) {
      _overflow = false;
      _visibleLeading = leading;
      shown = <int>[for (var i = 0; i < boxes.length; i++) i];
    } else if (_rowsFor(widths, limit) <= maxRows) {
      _overflow = false;
      _visibleLeading = leading;
      shown = <int>[for (var i = 0; i < boxes.length; i++) i];
    } else {
      _overflow = true;
      var keep = leading;
      while (keep > 0) {
        final candidate = <int>[
          for (var i = 0; i < keep; i++) i,
          if (hasTrailing) leading,
        ];
        if (_rowsFor(
                <double>[for (final i in candidate) widths[i]], limit) <=
            maxRows) {
          break;
        }
        keep--;
      }
      _visibleLeading = keep;
      shown = <int>[
        for (var i = 0; i < keep; i++) i,
        if (hasTrailing) leading,
      ];
    }

    final rows = <List<int>>[];
    var current = <int>[];
    var x = 0.0;
    for (final i in shown) {
      final w = widths[i];
      if (current.isEmpty) {
        current.add(i);
        x = w;
      } else if (x + _spacing + w <= limit + 1e-9) {
        current.add(i);
        x += _spacing + w;
      } else {
        rows.add(current);
        current = <int>[i];
        x = w;
      }
    }
    if (current.isNotEmpty) rows.add(current);

    var y = 0.0;
    var widest = 0.0;
    for (final row in rows) {
      var height = 0.0;
      var total = 0.0;
      for (var j = 0; j < row.length; j++) {
        final h = boxes[row[j]].size.height;
        if (h > height) height = h;
        total += (j == 0 ? 0.0 : _spacing) + widths[row[j]];
      }
      if (total > widest) widest = total;
      var runX = _textDirection == TextDirection.rtl && rawLimit.isFinite
          ? rawLimit - total
          : 0.0;
      for (final i in row) {
        final h = boxes[i].size.height;
        final dy = switch (_crossAxisAlignment) {
          WrapCrossAlignment.start => y,
          WrapCrossAlignment.center => y + (height - h) / 2,
          WrapCrossAlignment.end => y + (height - h),
        };
        (boxes[i].parentData! as ClampedWrapParentData).offset =
            Offset(runX, dy);
        runX += widths[i] + _spacing;
      }
      y += height + _runSpacing;
    }
    if (rows.isNotEmpty) y -= _runSpacing;

    for (var i = 0; i < boxes.length; i++) {
      if (!shown.contains(i)) {
        (boxes[i].parentData! as ClampedWrapParentData).offset =
            Offset.zero;
      }
    }

    size = Size(
      constraints.hasBoundedWidth ? constraints.maxWidth : widest,
      y,
    );

    if (_overflow != _notified && !_notifyScheduled) {
      _notifyScheduled = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _notifyScheduled = false;
        if (!attached || _notified == _overflow) return;
        _notified = _overflow;
        onOverflowChanged?.call(_overflow);
      });
    }
  }

  bool _isShown(RenderBox child) {
    RenderBox? current = firstChild;
    var index = 0;
    while (current != null) {
      if (identical(current, child)) {
        return index < _visibleLeading || index >= _leadingCount;
      }
      index++;
      current = childAfter(current);
    }
    return false;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    RenderBox? child = firstChild;
    while (child != null) {
      if (_isShown(child)) {
        final data = child.parentData! as ClampedWrapParentData;
        context.paintChild(child, offset + data.offset);
      }
      child = childAfter(child);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    RenderBox? child = lastChild;
    while (child != null) {
      if (_isShown(child)) {
        final data = child.parentData! as ClampedWrapParentData;
        if (result.addWithPaintOffset(
          offset: data.offset,
          position: position,
          hitTest: (hitResult, transformed) =>
              child!.hitTest(hitResult, position: transformed),
        )) {
          return true;
        }
      }
      child = childBefore(child);
    }
    return false;
  }
}
