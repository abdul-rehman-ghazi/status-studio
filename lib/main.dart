import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/app.dart';

void main() {
  runApp(const ProviderScope(child: StatusStudioApp()));
}
