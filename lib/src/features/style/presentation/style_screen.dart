import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:status_studio/src/core/error_messages.dart';
import 'package:status_studio/src/core/presentation/bottom_action.dart';
import 'package:status_studio/src/core/presentation/flow_app_bar.dart';
import 'package:status_studio/src/core/presentation/hint_text.dart';
import 'package:status_studio/src/core/presentation/option_row.dart';
import 'package:status_studio/src/core/presentation/route_animation.dart';
import 'package:status_studio/src/core/presentation/script_text.dart';
import 'package:status_studio/src/core/presentation/section_label.dart';
import 'package:status_studio/src/core/script_detection.dart';
import 'package:status_studio/src/features/branding/presentation/logo_mark.dart';
import 'package:status_studio/src/features/reel/application/reel_draft_controller.dart';
import 'package:status_studio/src/features/reel/domain/reel_draft.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/style/data/caption_translator.dart';
import 'package:status_studio/src/features/style/domain/caption_settings.dart';
import 'package:status_studio/src/features/style/domain/frame_settings.dart';
import 'package:status_studio/src/features/style/domain/roman_urdu.dart';
import 'package:status_studio/src/features/style/presentation/reel_preview.dart';
import 'package:status_studio/src/features/transcript/domain/line_selection.dart';
import 'package:status_studio/src/routing/app_router.dart';

const _previewMaxHeight = 380.0;

class StyleScreen extends ConsumerStatefulWidget {
  const StyleScreen({super.key});

  @override
  ConsumerState<StyleScreen> createState() => _StyleScreenState();
}

class _StyleScreenState extends ConsumerState<StyleScreen> with RouteAware {
  late final TextEditingController _captionController = TextEditingController(
    text: ref.read(reelDraftProvider).caption.text,
  );

  /// Bumped by every variant tap and edit, so a translation that finishes
  /// after the user moved on is dropped instead of overwriting their choice.
  var _variantRequest = 0;
  var _translating = false;

  /// True while Export is open: the preview's player holds a video decoder,
  /// and the phone's 1080p decoder has no memory left for the export's own
  /// (MediaCodec error -12 on the Redmi Note 11).
  var _previewReleased = false;
  late final RouteObserver<ModalRoute<void>> _routes = ref.read(
    routeObserverProvider,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ModalRoute.of(context) case final route?) {
      _routes.subscribe(this, route);
    }
  }

  /// Whatever Export became (it replaces itself with Done) has been popped, so
  /// the preview's player may come back once that route has slid away. Not on
  /// the push future: Export ending with Done never completes it.
  @override
  void didPopNext() {
    if (_previewReleased) {
      unawaited(_restorePreview());
    }
  }

  @override
  void dispose() {
    _routes.unsubscribe(this);
    _captionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(reelDraftProvider);
    final controller = ref.read(reelDraftProvider.notifier);
    final caption = draft.caption;
    return Scaffold(
      appBar: FlowAppBar(
        title: 'Caption',
        stepLabel: draft.lyricsSkipped ? 'Step 3 of 3' : 'Step 4 of 4',
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _framePreview(draft),
            const SizedBox(height: 24),
            const SectionLabel('Caption'),
            // Without a script there is nothing to translate (spec FR-29).
            if (!draft.lyricsSkipped)
              OptionRow<CaptionVariant>(
                options: _variantOptions(
                  draft,
                  ref.watch(captionTranslatorProvider),
                ),
                selected: caption.variant,
                onSelected: (variant) =>
                    unawaited(_switchVariant(draft, variant)),
              ),
            if (_translating) const _TranslatingNote(),
            const SizedBox(height: 10),
            TextField(
              controller: _captionController,
              minLines: 3,
              maxLines: 5,
              style: scriptTextStyle(_captionController.text),
              textDirection: _captionDirection(_captionController.text),
              decoration: const InputDecoration(border: OutlineInputBorder()),
              onChanged: (text) {
                _dropPendingVariant();
                controller.updateCaption(caption.copyWith(text: text));
              },
            ),
            const SizedBox(height: 8),
            HintText(
              draft.lyricsSkipped ? _ownCaptionHint : _scriptCaptionHint,
            ),
            const SizedBox(height: 20),
            _CaptionLayoutControls(
              caption: caption,
              onChanged: controller.updateCaption,
            ),
            const SizedBox(height: 24),
            const _BrandingNote(),
          ],
        ),
      ),
      bottomNavigationBar: BottomAction(
        child: FilledButton(
          onPressed: () => unawaited(_openExport()),
          child: const Text('Export reel'),
        ),
      ),
    );
  }

  /// Export starts only once this step's player is gone, and the player comes
  /// back only once Export has slid away: never two decoders at a time (the
  /// same rule as Fine-tune and Lyrics).
  Future<void> _openExport() async {
    // A second tap before the push must not open Export twice: two renders
    // would bring the decoder shortage back.
    if (_previewReleased) {
      return;
    }
    setState(() => _previewReleased = true);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) {
      return;
    }
    if (ModalRoute.of(context)?.isCurrent != true) {
      // Back was pressed meanwhile; pushing now would open Export over the
      // wrong screen.
      setState(() => _previewReleased = false);
      return;
    }
    unawaited(context.push(AppRoutes.export));
  }

  Future<void> _restorePreview() async {
    await untilDismissed(ModalRoute.of(context)?.secondaryAnimation);
    if (mounted) {
      setState(() => _previewReleased = false);
    }
  }

  Widget _framePreview(ReelDraft draft) {
    final output = outputSizeFor(draft.frame, previewSourceSize(ref, draft));
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = math.min(
          constraints.maxWidth,
          _previewMaxHeight * output.width / output.height,
        );
        return Center(
          child: _previewReleased
              ? ReelPreviewWithoutVideo(draft: draft, maxWidth: maxWidth)
              : ReelPreview(draft: draft, maxWidth: maxWidth),
        );
      },
    );
  }

  /// Replaces the caption with [variant]'s text, discarding edits (FR-7).
  Future<void> _switchVariant(ReelDraft draft, CaptionVariant variant) async {
    // Re-tapping the current chip is not a switch; keep the user's edits.
    if (variant == draft.caption.variant) {
      _dropPendingVariant();
      return;
    }
    if (_translating && variant == CaptionVariant.english) {
      return;
    }
    final request = ++_variantRequest;
    setState(() => _translating = variant == CaptionVariant.english);
    try {
      final text = await _variantText(draft, variant);
      if (!mounted || request != _variantRequest) {
        return;
      }
      _captionController.text = text;
      final controller = ref.read(reelDraftProvider.notifier);
      controller.updateCaption(
        ref
            .read(reelDraftProvider)
            .caption
            .copyWith(variant: variant, text: text),
      );
    } on Object catch (error) {
      if (request == _variantRequest) {
        _showTranslationFailure(error, () => _switchVariant(draft, variant));
      }
    } finally {
      if (mounted && request == _variantRequest) {
        setState(() => _translating = false);
      }
    }
  }

  /// The user chose something else: a translation still running is ignored.
  void _dropPendingVariant() {
    _variantRequest++;
    if (_translating) {
      setState(() => _translating = false);
    }
  }

  Future<String> _variantText(ReelDraft draft, CaptionVariant variant) {
    final original = _selectedLinesText(draft);
    return switch (variant) {
      CaptionVariant.original => Future.value(original),
      CaptionVariant.roman => Future.value(romanizeUrdu(original)),
      CaptionVariant.english =>
        ref
            .read(captionTranslatorProvider)
            .toEnglish(original, _languageCode(draft)),
    };
  }

  /// Spec §8: "English needs a one-time download." with Retry, or the
  /// general message for any other failure.
  void _showTranslationFailure(Object error, VoidCallback retry) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(errorMessageFor(error)),
        action: SnackBarAction(label: 'Retry', onPressed: retry),
      ),
    );
  }
}

class _TranslatingNote extends StatelessWidget {
  const _TranslatingNote();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 8),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 8),
          HintText('Translating…'),
        ],
      ),
    );
  }
}

const _scriptCaptionHint =
    'Filled from the lines inside the clip. Each line shows on its own, '
    'when it is said. Translation runs on your phone. Edit anything.';

const _ownCaptionHint =
    'Optional. Leave it empty for a reel with no caption. Each line shows on '
    'its own; the clip is shared out between them.';

String _languageCode(ReelDraft draft) =>
    draft.transcript?.languageCode ?? ScriptLanguage.auto.whisperCode;

String _selectedLinesText(ReelDraft draft) {
  final lines = draft.transcript?.lines ?? const [];
  return switch (draft.selection) {
    RangeSelected(:final start, :final end) =>
      lines.sublist(start, end + 1).map((line) => line.text).join('\n'),
    _ => draft.caption.text,
  };
}

TextDirection _captionDirection(String text) =>
    isArabicScript(text) ? TextDirection.rtl : TextDirection.ltr;

List<Option<CaptionVariant>> _variantOptions(
  ReelDraft draft,
  CaptionTranslator translator,
) {
  final languageCode = _languageCode(draft);
  return [
    (value: CaptionVariant.original, label: 'Original'),
    if (languageCode == ScriptLanguage.urdu.whisperCode)
      (value: CaptionVariant.roman, label: 'Roman'),
    if (translator.supports(languageCode))
      (value: CaptionVariant.english, label: 'English'),
  ];
}

class _CaptionLayoutControls extends StatelessWidget {
  const _CaptionLayoutControls({
    required this.caption,
    required this.onChanged,
  });

  final CaptionSettings caption;
  final ValueChanged<CaptionSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('Position'),
              OptionRow<CaptionPosition>(
                options: const [
                  (value: CaptionPosition.top, label: 'Top'),
                  (value: CaptionPosition.bottom, label: 'Bottom'),
                ],
                selected: caption.position,
                onSelected: (position) =>
                    onChanged(caption.copyWith(position: position)),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('Size'),
              OptionRow<CaptionSize>(
                options: const [
                  (value: CaptionSize.small, label: 'S'),
                  (value: CaptionSize.medium, label: 'M'),
                  (value: CaptionSize.large, label: 'L'),
                ],
                selected: caption.size,
                onSelected: (size) => onChanged(caption.copyWith(size: size)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BrandingNote extends StatelessWidget {
  const _BrandingNote();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        LogoMark(size: 32),
        SizedBox(width: 12),
        Expanded(
          child: HintText(
            'App name and logo are added to every reel, opposite the caption.',
          ),
        ),
      ],
    );
  }
}
