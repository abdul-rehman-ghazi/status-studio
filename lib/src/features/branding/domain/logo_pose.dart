/// Where the moving parts of the logo sit, in spec §7's 100-unit box.
class LogoPose {
  const LogoPose({required this.bracketInset, required this.barHalfLengths});

  /// How far each bracket has moved toward the middle.
  final double bracketInset;

  /// Half the height of each bar, left to right. Bars are centred on y 50.
  final List<double> barHalfLengths;

  /// The logo as §7 draws it.
  static const rest = LogoPose(
    bracketInset: 0,
    barHalfLengths: [8, 15, 20, 13, 7],
  );
}
