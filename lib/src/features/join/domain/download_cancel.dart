import 'package:status_studio/src/features/join/domain/join_errors.dart';

/// Cancel on the making view (spec FR-37): downloads check it between
/// chunks and stop with [DownloadCancelledException].
class DownloadCancel {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;

  void throwIfCancelled() {
    if (_cancelled) {
      throw const DownloadCancelledException();
    }
  }
}
