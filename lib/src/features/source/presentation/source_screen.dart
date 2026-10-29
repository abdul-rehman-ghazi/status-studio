import 'package:flutter/material.dart';

class SourceScreen extends StatelessWidget {
  const SourceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New reel')),
      body: const Padding(
        padding: EdgeInsets.all(20),
        child: TextField(
          decoration: InputDecoration(labelText: 'YouTube link'),
        ),
      ),
    );
  }
}
