import 'package:flutter/material.dart';

/// The full-width button(s) pinned to the bottom of a flow screen.
class BottomAction extends StatelessWidget {
  const BottomAction({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: SizedBox(width: double.infinity, height: 52, child: child),
    );
  }
}
