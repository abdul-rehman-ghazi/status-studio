import 'package:flutter/material.dart';
import 'package:status_studio/src/core/presentation/screen_title.dart';
import 'package:status_studio/src/features/source/presentation/link_section.dart';

/// From a YouTube link (spec FR-35, FR-36, Android only): read a link, then
/// ask for a topic and a length. Opened from Home or by a shared link.
class LinkScreen extends StatelessWidget {
  const LinkScreen({this.sharedLink, super.key});

  /// A link shared into the app; it is filled in and read at once.
  final String? sharedLink;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const ScreenTitle('From a link')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [LinkSection(sharedLink: sharedLink)],
      ),
    );
  }
}
