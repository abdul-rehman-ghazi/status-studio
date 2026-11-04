import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Why Script opens with a message: a kept fine-tune could not be continued
/// (spec FR-24, §8).
enum ScriptOpeningNotice {
  fineTuneScriptGone(
    "This fine-tune's script had to be written again. Pick the lines again; "
    'the size and caption style are kept.',
  ),
  fineTuneScriptChanged(
    'The script changed since this fine-tune was saved. Pick the lines '
    'again; the size and caption style are kept.',
  );

  const ScriptOpeningNotice(this.message);

  final String message;
}

typedef PendingScriptNotice = ({String videoId, ScriptOpeningNotice notice});

/// The message Script shows once when it opens for [PendingScriptNotice.videoId].
final scriptOpeningNoticeProvider =
    NotifierProvider<ScriptOpeningNoticeController, PendingScriptNotice?>(
      ScriptOpeningNoticeController.new,
    );

class ScriptOpeningNoticeController extends Notifier<PendingScriptNotice?> {
  @override
  PendingScriptNotice? build() => null;

  void show(String videoId, ScriptOpeningNotice notice) =>
      state = (videoId: videoId, notice: notice);

  void clear() => state = null;
}
