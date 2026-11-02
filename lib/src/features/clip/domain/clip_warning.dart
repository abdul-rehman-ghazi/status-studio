import 'package:status_studio/src/features/clip/domain/clip_range.dart';

/// Until WhatsApp's current limit is confirmed (spec §10 Q3), clips past
/// 60 s get a warning, never a block.
const _statusLimit = Duration(seconds: 60);

bool isLongerThanStatusLimit(ClipRange clip) => clip.length > _statusLimit;
