import 'dart:convert';
import 'dart:io';

/// Throws [FormatException] when [file] doesn't hold a JSON object.
Future<Map<String, Object?>> readJsonObject(File file) async {
  final decoded = jsonDecode(await file.readAsString());
  if (decoded is Map<String, Object?>) {
    return decoded;
  }
  throw const FormatException('Not a JSON object.');
}

/// Written as `.part` and renamed, so a crash leaves the old file or the new
/// one, never half of either.
Future<void> writeJsonAtomically(File target, Map<String, Object?> json) async {
  await target.parent.create(recursive: true);
  final part = File('${target.path}.part');
  await part.writeAsString(jsonEncode(json), flush: true);
  await part.rename(target.path);
}
