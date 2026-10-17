// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../utils/toast.dart';
import '../../../library/domain/game_editor.dart';
import '../../../library/domain/runner_detection.dart';

/// Opens a folder in the system file manager. Overridden in tests so no real
/// file manager ever opens.
final folderOpenerProvider = Provider<Future<bool> Function(Uri)>(
  (ref) => launchUrl,
);

/// Picks a folder, rejecting Flatpak-portal paths with a toast.
Future<String?> pickFolderOrNull(WidgetRef ref, BuildContext context) async {
  final picked = await ref.read(pathPickerProvider)(mode: PathPickMode.folder);
  if (picked == null || picked.isEmpty || !context.mounted) return null;
  if (isPortalPath(picked)) {
    Toast(context).show(portalPathMessage);
    return null;
  }
  return picked;
}

/// A titled block inside a settings section, separated by a thin rule.
///
/// With a [control] the title and subtitle form one row with the control on
/// the right. Otherwise [child] sits under the heading at full width.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    super.key,
    required this.title,
    this.subtitle,
    this.subtitleWidget,
    this.control,
    this.footer,
    this.child,
    this.divider = true,
    this.rowKey,
  });

  final String title;
  final String? subtitle;
  final Widget? subtitleWidget;
  final Widget? control;
  final Widget? footer;
  final Widget? child;
  final bool divider;
  final Key? rowKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: theme.textTheme.titleMedium),
        if (subtitle != null || subtitleWidget != null) ...[
          const SizedBox(height: 2),
          subtitleWidget ??
              Text(
                subtitle!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
        ],
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (control != null)
          Row(
            key: rowKey,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: heading),
              const SizedBox(width: 24),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Align(
                  alignment: Alignment.centerRight,
                  widthFactor: 1,
                  heightFactor: 1,
                  child: control,
                ),
              ),
            ],
          )
        else ...[
          heading,
          const SizedBox(height: 12),
          child!,
        ],
        if (footer != null)
          Padding(padding: const EdgeInsets.only(top: 12), child: footer),
        if (divider)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Divider(height: 1, color: theme.colorScheme.outlineVariant),
          ),
      ],
    );
  }
}

/// Setting name and optional hint on the left, a bounded control on the right.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    this.label,
    this.hint,
    required this.control,
    this.controlWidth = 280,
  });

  final String? label;
  final String? hint;
  final Widget control;
  final double controlWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (label != null) Text(label!, style: theme.textTheme.bodyLarge),
              if (hint != null)
                Padding(
                  padding: EdgeInsets.only(top: label == null ? 0 : 2),
                  child: Text(
                    hint!,
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: controlWidth),
          child: control,
        ),
      ],
    );
  }
}

/// Selectable single-line text that shortens from the middle when it does
/// not fit, with the full value in a tooltip.
class MiddleEllipsisText extends StatelessWidget {
  const MiddleEllipsisText({
    super.key,
    required this.text,
    this.style,
    this.tooltip,
  });

  final String text;
  final TextStyle? style;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final effective = DefaultTextStyle.of(context).style.merge(style);
    return LayoutBuilder(
      builder: (context, constraints) {
        var shown = text;
        if (constraints.hasBoundedWidth) {
          bool overflows(String value) => (TextPainter(
            text: TextSpan(text: value, style: effective),
            maxLines: 1,
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout(maxWidth: constraints.maxWidth)).didExceedMaxLines;
          if (overflows(text)) {
            var head = text.length ~/ 2;
            var tail = text.length - head;
            while (head > 0 && tail > 0) {
              final candidate =
                  '${text.substring(0, head)}…'
                  '${text.substring(text.length - tail)}';
              if (!overflows(candidate)) {
                shown = candidate;
                break;
              }
              head--;
              tail--;
            }
            if (shown == text) shown = '…';
          }
        }
        return Tooltip(
          message: tooltip ?? text,
          child: SelectionArea(
            child: Text(
              shown,
              style: effective,
              maxLines: 1,
              overflow: TextOverflow.clip,
            ),
          ),
        );
      },
    );
  }
}

/// A selectable row with a radio dot, used for inline choice groups.
class SettingsRadioOption extends StatelessWidget {
  const SettingsRadioOption({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          hoverColor: scheme.onSurface.withValues(alpha: 0.06),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? scheme.primary : scheme.outline,
                        width: 2,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: selected
                        ? Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: scheme.primary,
                            ),
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Outlined 40 px control with a hover border.
class SettingsControlBox extends StatefulWidget {
  const SettingsControlBox({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.only(left: 12, right: 8),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  State<SettingsControlBox> createState() => _SettingsControlBoxState();
}

class _SettingsControlBoxState extends State<SettingsControlBox> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        height: 40,
        padding: widget.padding,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _hovered
                ? scheme.onSurface.withValues(alpha: 0.18)
                : scheme.outlineVariant,
          ),
        ),
        child: widget.child,
      ),
    );
  }
}

/// The shared text box: a filled, outlined box exactly [height] px tall (or
/// at least [minHeight] when multi-line). The border is painted over the
/// content, so the field inside keeps the full height. [overlay] paints a middle-ellipsized value over an
/// unfocused path.
class SettingsTextBox extends StatefulWidget {
  const SettingsTextBox({
    super.key,
    this.controller,
    this.focusNode,
    this.hint,
    this.height = 40,
    this.minHeight,
    this.minLines,
    this.maxLines = 1,
    this.keyboardType,
    this.autofocus = false,
    this.onSubmitted,
    this.overlay,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? hint;
  final double height;
  final double? minHeight;
  final int? minLines;
  final int? maxLines;
  final TextInputType? keyboardType;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;
  final String? overlay;

  @override
  State<SettingsTextBox> createState() => _SettingsTextBoxState();
}

class _SettingsTextBoxState extends State<SettingsTextBox> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final multiline = widget.maxLines != 1;
    final edge = _focused
        ? scheme.primary
        : _hovered
        ? scheme.onSurface.withValues(alpha: 0.18)
        : scheme.outlineVariant;
    final field = Focus(
      canRequestFocus: false,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: TextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        keyboardType: widget.keyboardType,
        minLines: widget.minLines,
        maxLines: widget.maxLines,
        style: theme.textTheme.bodyMedium,
        textAlignVertical: multiline
            ? TextAlignVertical.top
            : TextAlignVertical.center,
        strutStyle: StrutStyle.disabled,
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
          isDense: true,
          border: InputBorder.none,
          // Single-line text sits 4 px lower to match the dropdown values.
          contentPadding: multiline
              ? const EdgeInsets.symmetric(vertical: 10)
              : const EdgeInsets.fromLTRB(0, 14, 0, 6),
        ),
        onSubmitted: widget.onSubmitted,
      ),
    );
    final inner = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 12,
        vertical: multiline ? 10 : 0,
      ),
      child: multiline ? field : SizedBox(width: double.infinity, child: field),
    );
    final overlay = widget.overlay;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        height: multiline ? null : widget.height,
        constraints: multiline && widget.minHeight != null
            ? BoxConstraints(minHeight: widget.minHeight!)
            : null,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: edge, width: _focused ? 2 : 1),
        ),
        child: overlay == null || _focused || overlay.isEmpty
            ? inner
            : Stack(
                fit: StackFit.expand,
                children: [
                  inner,
                  MiddleEllipsisValue(text: overlay),
                ],
              ),
      ),
    );
  }
}

/// A 40 px outlined dropdown with the shared control look.
class SettingsDropdown<T> extends StatelessWidget {
  const SettingsDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.hint,
  });

  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final Widget? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SettingsControlBox(
      padding: const EdgeInsets.only(left: 12, right: 4),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          hint: hint,
          isExpanded: true,
          isDense: true,
          icon: const Icon(Icons.arrow_drop_down_rounded),
          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurface),
          dropdownColor: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(10),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

/// Plain settings text field with the shared 40 px outlined look.
class SettingsTextField extends StatefulWidget {
  const SettingsTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.hint,
    this.onSubmitted,
    this.autofocus = false,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? hint;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  @override
  State<SettingsTextField> createState() => _SettingsTextFieldState();
}

class _SettingsTextFieldState extends State<SettingsTextField> {
  @override
  Widget build(BuildContext context) {
    return SettingsTextBox(
      controller: widget.controller,
      focusNode: widget.focusNode,
      hint: widget.hint,
      autofocus: widget.autofocus,
      onSubmitted: widget.onSubmitted,
    );
  }
}

/// Read-only value drawn over a 40 px control box, shortened from the middle.
class MiddleEllipsisValue extends StatelessWidget {
  const MiddleEllipsisValue({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IgnorePointer(
      child: Padding(
        padding: const EdgeInsets.all(1),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: ColoredBox(
            color: theme.colorScheme.surfaceContainer,
            child: Padding(
              padding: const EdgeInsets.only(left: 12, right: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: MiddleEllipsisText(
                  text: text,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A prefs text field that saves on blur or Enter and reverts on Esc.
class PrefTextField extends ConsumerStatefulWidget {
  const PrefTextField({
    super.key,
    required this.initial,
    this.hint,
    this.isPath = false,
    this.middleEllipsis = false,
    required this.onSave,
  });

  final String initial;
  final String? hint;
  final bool isPath;

  /// Shows the value shortened from the middle while the field is unfocused.
  final bool middleEllipsis;
  final void Function(String text) onSave;

  @override
  ConsumerState<PrefTextField> createState() => _PrefTextFieldState();
}

class _PrefTextFieldState extends ConsumerState<PrefTextField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  String _focusValue = '';
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(PrefTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus &&
        oldWidget.initial != widget.initial &&
        _controller.text == oldWidget.initial) {
      _controller.text = widget.initial;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocus);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocus() {
    setState(() => _focused = _focusNode.hasFocus);
    if (_focusNode.hasFocus) {
      _focusValue = _controller.text;
    } else {
      _submit();
    }
  }

  void _submit() {
    final text = _controller.text;
    if (text == _focusValue) return;
    _focusValue = text;
    if (widget.isPath && text.isNotEmpty && isPortalPath(text)) {
      if (mounted) {
        Toast(context).show(portalPathMessage);
        _controller.text = widget.initial;
        _focusValue = _controller.text;
      }
      return;
    }
    widget.onSave(text);
  }

  void _cancel() {
    _controller.text = _focusValue;
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final overlay = widget.middleEllipsis && !_focused
        ? _controller.text
        : null;
    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _cancel();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: SettingsTextBox(
        controller: _controller,
        focusNode: _focusNode,
        hint: widget.hint,
        overlay: overlay,
        onSubmitted: (_) => _submit(),
      ),
    );
  }
}
