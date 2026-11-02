import 'package:flutter/foundation.dart';

/// Work that keeps running when the user leaves the app (spec FR-16).
enum BackgroundJob {
  script(resultNotificationId: 2),
  export(resultNotificationId: 3);

  const BackgroundJob({required this.resultNotificationId});

  /// One result per job, so a new script result replaces the last one
  /// without touching an export's.
  final int resultNotificationId;
}

/// The ongoing notification while a job runs.
@immutable
class ProgressNotice {
  const ProgressNotice({
    required this.title,
    required this.text,
    required this.percent,
  });

  /// The running step, e.g. "Writing the script".
  final String title;

  /// The video the work is for.
  final String text;
  final int percent;

  /// `45 % · Never Gonna Give You Up`.
  String get body => '$percent % · $text';

  @override
  bool operator ==(Object other) =>
      other is ProgressNotice &&
      other.title == title &&
      other.text == text &&
      other.percent == percent;

  @override
  int get hashCode => Object.hash(title, text, percent);
}

/// How a job ended, posted when the app isn't on screen.
@immutable
class ResultNotice {
  const ResultNotice({required this.title, required this.text});

  final String title;
  final String text;

  @override
  bool operator ==(Object other) =>
      other is ResultNotice && other.title == title && other.text == text;

  @override
  int get hashCode => Object.hash(title, text);
}
