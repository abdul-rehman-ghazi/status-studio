/// The installed app's version and build number, from `pubspec.yaml`.
class AppVersion {
  const AppVersion({required this.version, required this.build});

  final String version;
  final String build;

  /// "0.1.0 (1)", as About and support messages show it (spec FR-31).
  String get shown => '$version ($build)';
}
