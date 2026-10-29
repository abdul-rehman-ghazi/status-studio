import 'package:flutter/material.dart';
import 'package:status_studio/src/core/presentation/flow_app_bar.dart';

class ScriptScreen extends StatelessWidget {
  const ScriptScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      appBar: FlowAppBar(title: 'Pick the lines', stepLabel: 'Step 2 of 4'),
    );
  }
}
