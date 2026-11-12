import 'package:json_annotation/json_annotation.dart';

/// A [Duration] saved as whole milliseconds, as every saved file has done
/// since before M42.
class MillisecondsConverter implements JsonConverter<Duration, int> {
  const MillisecondsConverter();

  @override
  Duration fromJson(int milliseconds) => Duration(milliseconds: milliseconds);

  @override
  int toJson(Duration duration) => duration.inMilliseconds;
}

/// A `readValue` that hands a field the whole object, for a field whose
/// parts are saved flat beside the others (`json_serializable` can't
/// flatten). Its model writes `toJson` by hand to match.
Object? readWholeObject(Map<dynamic, dynamic> json, String key) => json;
