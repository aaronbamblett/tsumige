// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter/widgets.dart';

/// A [FileImage] whose cache identity includes the file's version, so a file
/// replaced at the same path is decoded again instead of served from the
/// image cache.
class VersionedFileImage extends FileImage {
  const VersionedFileImage(super.file, {required this.version});

  final String version;

  @override
  bool operator ==(Object other) =>
      other is VersionedFileImage &&
      other.file.path == file.path &&
      other.scale == scale &&
      other.version == version;

  @override
  int get hashCode => Object.hash(file.path, scale, version);
}

/// Image provider for a cover or background file, decoded at [cacheWidth]
/// when given. Use it everywhere a stored art file is drawn.
ImageProvider artFileImage(File file, {int? cacheWidth}) {
  final stat = file.statSync();
  final image = VersionedFileImage(
    file,
    version: '${stat.modified.microsecondsSinceEpoch}:${stat.size}',
  );
  return cacheWidth == null ? image : ResizeImage(image, width: cacheWidth);
}
