import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/features/reel/domain/fine_tune_draft.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/style/domain/caption_settings.dart';
import 'package:status_studio/src/features/style/domain/crop_path.dart';
import 'package:status_studio/src/features/style/domain/frame_settings.dart';
import 'package:status_studio/src/features/transcript/domain/line_selection.dart';

const fineTuneDraftVersion = 2;

/// Version 1 kept one draft per video and language, always with lines.
const _versionWithLanguageFiles = 1;

// A rounding slack so a free crop saved at the frame's edge still reads back.
const _edgeSlack = 1e-9;

Map<String, Object?> fineTuneDraftToJson(FineTuneDraft draft) => {
  'version': fineTuneDraftVersion,
  'savedAt': draft.savedAt.toUtc().toIso8601String(),
  'videoId': draft.videoId,
  'language': draft.language.whisperCode,
  'lyricsShown': draft.lyricsShown,
  'fadeEnds': draft.fadeEnds,
  'louderSound': draft.louderSound,
  'linesEdited': draft.linesEdited,
  if (draft.lines case final lines?) 'lines': _linesToJson(lines),
  'clip': {
    'startMs': draft.clip.start.inMilliseconds,
    'endMs': draft.clip.end.inMilliseconds,
  },
  'frame': _frameToJson(draft.frame),
  'caption': _captionToJson(draft.caption),
};

/// Throws [FormatException] when [json] is not a version 1 or 2 fine-tune.
FineTuneDraft fineTuneDraftFromJson(Map<String, Object?> json) {
  return switch (json['version']) {
    fineTuneDraftVersion => _draftFromJson(json, lines: _optionalLines(json)),
    _versionWithLanguageFiles => _draftFromJson(
      json,
      lines: KeptLines(
        selection: _selectionFromJson(_object(json['selection'])),
        fingerprint: _integer(json['scriptFingerprint']),
      ),
    ),
    _ => throw const FormatException('Not a version 1 or 2 fine-tune.'),
  };
}

FineTuneDraft _draftFromJson(
  Map<String, Object?> json, {
  required KeptLines? lines,
}) {
  return FineTuneDraft(
    videoId: _string(json['videoId']),
    language: _language(json['language']),
    // Version 1 had no switch: its reels always had lyrics.
    lyricsShown: json['lyricsShown'] == null
        ? true
        : _boolean(json['lyricsShown']),
    // Files kept before M38 have no fade (spec FR-33).
    fadeEnds: json['fadeEnds'] == null ? false : _boolean(json['fadeEnds']),
    // Files kept before M52 have no boost (spec FR-42).
    louderSound: json['louderSound'] == null
        ? false
        : _boolean(json['louderSound']),
    lines: lines,
    clip: _clipFromJson(_object(json['clip'])),
    frame: _frameFromJson(_object(json['frame'])),
    caption: _captionFromJson(_object(json['caption'])),
    linesEdited: _boolean(json['linesEdited']),
    savedAt: DateTime.parse(_string(json['savedAt'])),
  );
}

KeptLines? _optionalLines(Map<String, Object?> json) {
  final lines = json['lines'];
  if (lines == null) {
    return null;
  }
  final object = _object(lines);
  return KeptLines(
    selection: _selectionFromJson(object),
    fingerprint: _integer(object['fingerprint']),
  );
}

Map<String, Object?> _linesToJson(KeptLines lines) => {
  'start': lines.selection.start,
  'end': lines.selection.end,
  'fingerprint': lines.fingerprint,
};

Map<String, Object?> _frameToJson(FrameSettings frame) => {
  'preset': frame.preset.name,
  'fill': frame.fill.name,
  'anchor': _anchorToJson(frame.anchor),
  'freeCrop': {
    'left': frame.freeCrop.left,
    'top': frame.freeCrop.top,
    'width': frame.freeCrop.width,
    'height': frame.freeCrop.height,
  },
  'keyframes': frame.cropPath.keyframes.map(_keyframeToJson).toList(),
};

Map<String, Object?> _anchorToJson(CropAnchor anchor) => {
  'x': anchor.x,
  'y': anchor.y,
};

Map<String, Object?> _keyframeToJson(CropKeyframe keyframe) => {
  'timeMs': keyframe.time.inMilliseconds,
  ..._anchorToJson(keyframe.anchor),
  'arrival': keyframe.arrival.name,
};

Map<String, Object?> _captionToJson(CaptionSettings caption) => {
  'text': caption.text,
  'position': caption.position.name,
  'size': caption.size.name,
  'look': caption.appearance.look.name,
  'boxColours': caption.appearance.boxColours.name,
  'shadowColours': caption.appearance.shadowColours.name,
};

RangeSelected _selectionFromJson(Map<String, Object?> json) {
  final start = _integer(json['start']);
  final end = _integer(json['end']);
  if (start < 0 || end < start) {
    throw const FormatException('Bad line range.');
  }
  return RangeSelected(start, end);
}

ClipRange _clipFromJson(Map<String, Object?> json) {
  final startMs = _integer(json['startMs']);
  final endMs = _integer(json['endMs']);
  if (startMs < 0 || endMs <= startMs) {
    throw const FormatException('Bad clip.');
  }
  return ClipRange(
    start: Duration(milliseconds: startMs),
    end: Duration(milliseconds: endMs),
  );
}

FrameSettings _frameFromJson(Map<String, Object?> json) => FrameSettings(
  preset: _enumByName(AspectPreset.values, json['preset']),
  fill: _enumByName(FillMode.values, json['fill']),
  anchor: _anchorFromJson(_object(json['anchor'])),
  freeCrop: _freeCropFromJson(_object(json['freeCrop'])),
  cropPath: CropPath(_keyframesFromJson(_list(json['keyframes']))),
);

CropAnchor _anchorFromJson(Map<String, Object?> json) {
  final x = _number(json['x']);
  final y = _number(json['y']);
  if (!_isFraction(x) || !_isFraction(y)) {
    throw const FormatException('Anchor outside 0..1.');
  }
  return CropAnchor(x: x, y: y);
}

FreeCropRect _freeCropFromJson(Map<String, Object?> json) {
  final crop = FreeCropRect(
    left: _number(json['left']),
    top: _number(json['top']),
    width: _number(json['width']),
    height: _number(json['height']),
  );
  final fits =
      _isFraction(crop.left) &&
      _isFraction(crop.top) &&
      crop.width > 0 &&
      crop.height > 0 &&
      crop.left + crop.width <= 1 + _edgeSlack &&
      crop.top + crop.height <= 1 + _edgeSlack;
  if (!fits) {
    throw const FormatException('Free crop outside the frame.');
  }
  return crop;
}

List<CropKeyframe> _keyframesFromJson(List<Object?> entries) {
  final keyframes = entries
      .map((entry) => _keyframeFromJson(_object(entry)))
      .toList();
  for (var index = 1; index < keyframes.length; index++) {
    if (keyframes[index].time <= keyframes[index - 1].time) {
      throw const FormatException('Keyframes out of order.');
    }
  }
  return keyframes;
}

CropKeyframe _keyframeFromJson(Map<String, Object?> json) {
  final timeMs = _integer(json['timeMs']);
  if (timeMs < 0) {
    throw const FormatException('Keyframe before the start.');
  }
  return CropKeyframe(
    time: Duration(milliseconds: timeMs),
    anchor: _anchorFromJson(json),
    arrival: _enumByName(CropArrival.values, json['arrival']),
  );
}

CaptionSettings _captionFromJson(Map<String, Object?> json) => CaptionSettings(
  text: _string(json['text']),
  position: _enumByName(CaptionPosition.values, json['position']),
  size: _enumByName(CaptionSize.values, json['size']),
  appearance: _appearanceFromJson(json),
);

/// Files kept before M37 have no appearance, and a later version may name
/// a colour this one doesn't know; both read as the default (spec FR-7).
CaptionAppearance _appearanceFromJson(Map<String, Object?> json) {
  const fallback = CaptionAppearance();
  return CaptionAppearance(
    look: CaptionLook.values.asNameMap()[json['look']] ?? fallback.look,
    boxColours:
        BoxColours.values.asNameMap()[json['boxColours']] ??
        fallback.boxColours,
    shadowColours:
        ShadowColours.values.asNameMap()[json['shadowColours']] ??
        fallback.shadowColours,
  );
}

ScriptLanguage _language(Object? code) {
  final name = _string(code);
  return ScriptLanguage.values.firstWhere(
    (language) => language.whisperCode == name,
    orElse: () => throw FormatException('Unknown language $name.'),
  );
}

T _enumByName<T extends Enum>(List<T> values, Object? name) {
  final text = _string(name);
  return values.firstWhere(
    (value) => value.name == text,
    orElse: () => throw FormatException('Unknown name $text.'),
  );
}

bool _isFraction(double value) => value >= 0 && value <= 1;

String _string(Object? value) =>
    value is String ? value : throw const FormatException('Expected text.');

int _integer(Object? value) => value is int
    ? value
    : throw const FormatException('Expected a whole number.');

double _number(Object? value) => value is num
    ? value.toDouble()
    : throw const FormatException('Expected a number.');

bool _boolean(Object? value) => value is bool
    ? value
    : throw const FormatException('Expected true or false.');

Map<String, Object?> _object(Object? value) => value is Map<String, Object?>
    ? value
    : throw const FormatException('Expected an object.');

List<Object?> _list(Object? value) => value is List<Object?>
    ? value
    : throw const FormatException('Expected a list.');
