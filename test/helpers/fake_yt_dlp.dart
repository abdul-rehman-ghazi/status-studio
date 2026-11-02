import 'package:status_studio/src/features/source/data/yt_dlp.dart';

/// Answers with [quick] and [full] JSON, counting each kind of run. A
/// missing answer fails the run with [failure].
class FakeYtDlp implements YtDlp {
  FakeYtDlp({this.quick, this.full, this.failure});

  Map<String, Object?>? quick;
  Map<String, Object?>? full;
  Exception? failure;

  /// What the full run answers once yt-dlp has been updated, when set.
  Map<String, Object?>? fullAfterUpdate;
  var quickRuns = 0;
  var fullRuns = 0;
  var updates = 0;

  @override
  Future<Map<String, Object?>> quickVideoInfo(String videoId) async {
    quickRuns++;
    return quick ?? (throw failure!);
  }

  @override
  Future<Map<String, Object?>> videoInfo(String videoId) async {
    fullRuns++;
    if (updates > 0 && fullAfterUpdate != null) {
      return fullAfterUpdate!;
    }
    return full ?? (throw failure!);
  }

  @override
  Future<YtDlpUpdate> update() async {
    updates++;
    return YtDlpUpdate.updated;
  }

  @override
  Future<String> version() async => '2026.10.26';
}
