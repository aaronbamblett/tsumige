// Copyright (c) 2022 Contributors to the Suwayomi project
// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

enum SearchFieldHintBehavior { auto, forceHint, forceLabel }

/// A search text field driven by a plain string: [onChanged] reports the
/// current text (null when cleared), with no query DSL or provider wiring.
class SearchField extends HookWidget {
  const SearchField({
    super.key,
    this.onChanged,
    this.onClose,
    this.initialText,
    this.onSubmitted,
    this.labelText,
    this.hintText,
    this.autofocus = true,
    this.actions,
    this.hintBehavior = SearchFieldHintBehavior.auto,
  });
  final String? labelText;
  final String? hintText;
  final String? initialText;
  final ValueChanged<String?>? onChanged;
  final ValueChanged<String?>? onSubmitted;
  final VoidCallback? onClose;
  final bool autofocus;
  final List<Widget>? actions;

  final SearchFieldHintBehavior hintBehavior;

  @override
  Widget build(BuildContext context) {
    final controller =
        useMemoized(() => TextEditingController(text: initialText), const []);
    useEffect(() => controller.dispose, [controller]);

    final focusNode = useFocusNode();
    useListenable(focusNode);

    void closeAction() {
      controller.clear();
      onClose?.call();
      onChanged?.call(null);
      onSubmitted?.call(null);
    }

    void prefixAction() {
      if (focusNode.hasFocus) {
        focusNode.unfocus();
        closeAction();
      } else {
        focusNode.requestFocus();
      }
    }

    const unfocusedText = 'Search';
    final focusedText = hintText ?? labelText ?? unfocusedText;
    final (String? decorationLabel, String? decorationHint) = switch (hintBehavior) {
      SearchFieldHintBehavior.auto => (labelText ?? unfocusedText, hintText),
      SearchFieldHintBehavior.forceHint => (
          null,
          focusNode.hasFocus ? focusedText : (labelText ?? unfocusedText)
        ),
      SearchFieldHintBehavior.forceLabel => (
          focusNode.hasFocus ? focusedText : (labelText ?? unfocusedText),
          null
        ),
    };

    final closeIcon = onClose != null
        ? IconButton(
            onPressed: closeAction,
            icon: const Icon(Icons.close_rounded),
          )
        : null;

    return TextField(
      onChanged: onChanged,
      autofocus: autofocus,
      controller: controller,
      focusNode: focusNode,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        isDense: true,
        border: const OutlineInputBorder(),
        labelText: decorationLabel,
        hintText: decorationHint,
        prefixIcon: IconButton(
          icon: Icon(focusNode.hasFocus
              ? Icons.arrow_back_rounded
              : Icons.search_rounded),
          onPressed: prefixAction,
        ),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...?actions,
            ?closeIcon,
          ],
        ),
      ),
    );
  }
}
