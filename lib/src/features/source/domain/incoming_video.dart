import 'package:flutter/foundation.dart';

/// A video another app shared into this one, already copied into app
/// storage (spec FR-1). The importer moves [path] into `sources/<videoId>/`.
@immutable
class IncomingVideo {
  const IncomingVideo({required this.path, required this.displayName});

  final String path;

  /// The sender's file name, with its extension.
  final String displayName;

  @override
  bool operator ==(Object other) =>
      other is IncomingVideo &&
      other.path == path &&
      other.displayName == displayName;

  @override
  int get hashCode => Object.hash(path, displayName);
}
