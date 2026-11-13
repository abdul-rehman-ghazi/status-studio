import 'package:flutter/foundation.dart';

/// Something another app shared into this one: a video (spec FR-1) or, on
/// Android, a YouTube link (FR-35).
sealed class IncomingShare {
  const IncomingShare();
}

/// A video another app shared into this one, already copied into app
/// storage (spec FR-1). The importer moves [path] into `sources/<videoId>/`.
@immutable
class IncomingVideo extends IncomingShare {
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

/// A YouTube link shared as text (spec FR-35); Source fills it in and reads
/// it.
@immutable
class IncomingLink extends IncomingShare {
  const IncomingLink(this.link);

  final String link;

  @override
  bool operator ==(Object other) => other is IncomingLink && other.link == link;

  @override
  int get hashCode => link.hashCode;
}
