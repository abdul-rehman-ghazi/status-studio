import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/reel/application/reel_draft_controller.dart';
import 'package:status_studio/src/features/transcript/application/script_opening_notice.dart';

/// Shows, once, why Fine-tune opened on a rewritten script instead of the
/// kept one (spec FR-24).
class ScriptOpeningNoticeHost extends ConsumerStatefulWidget {
  const ScriptOpeningNoticeHost({super.key});

  @override
  ConsumerState<ScriptOpeningNoticeHost> createState() =>
      _ScriptOpeningNoticeHostState();
}

class _ScriptOpeningNoticeHostState
    extends ConsumerState<ScriptOpeningNoticeHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showPendingNotice());
  }

  void _showPendingNotice() {
    final pending = ref.read(scriptOpeningNoticeProvider);
    if (!mounted || pending == null) {
      return;
    }
    ref.read(scriptOpeningNoticeProvider.notifier).clear();
    final videoId = ref.read(reelDraftProvider).video?.videoId;
    if (pending.videoId != videoId) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(pending.notice.message)));
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
