import 'package:flutter/material.dart';

/// The app's theme as the user chose it in Appearance (spec FR-32).
enum ThemeChoice {
  light('Light', ThemeMode.light),
  dark('Dark', ThemeMode.dark),
  system('System', ThemeMode.system);

  const ThemeChoice(this.label, this.mode);

  final String label;
  final ThemeMode mode;
}
