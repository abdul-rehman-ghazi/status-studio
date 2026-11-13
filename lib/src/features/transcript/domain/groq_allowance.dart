/// Groq's hourly audio allowance as its last reply reported it (spec
/// FR-45).
class GroqAllowance {
  const GroqAllowance({
    required this.limit,
    required this.remaining,
    required this.resetsAt,
    required this.seenAt,
  });

  factory GroqAllowance.fromJson(Map<String, Object?> json) => GroqAllowance(
    limit: Duration(seconds: json['limitSeconds']! as int),
    remaining: Duration(seconds: json['remainingSeconds']! as int),
    resetsAt: DateTime.parse(json['resetsAt']! as String),
    seenAt: DateTime.parse(json['seenAt']! as String),
  );

  final Duration limit;
  final Duration remaining;
  final DateTime resetsAt;

  /// When the reply carrying these figures arrived.
  final DateTime seenAt;

  /// From the reset time on Groq has refilled the hour, so the whole limit
  /// is left.
  Duration leftAt(DateTime now) => hasRefilledBy(now) ? limit : remaining;

  bool hasRefilledBy(DateTime now) => !now.isBefore(resetsAt);

  Map<String, Object?> toJson() => {
    'limitSeconds': limit.inSeconds,
    'remainingSeconds': remaining.inSeconds,
    'resetsAt': resetsAt.toIso8601String(),
    'seenAt': seenAt.toIso8601String(),
  };
}

final _durationPart = RegExp(r'(\d+(?:\.\d+)?)(ms|h|m|s)');

/// Reads Groq's reset durations such as `2m12s`, `7.66s`, `1h2m3s` or
/// `250ms`. Throws [FormatException] for anything else.
Duration parseGroqDuration(String text) {
  final parts = _durationPart.allMatches(text).toList();
  final matched = parts.map((part) => part[0]!).join();
  if (parts.isEmpty || matched != text.trim()) {
    throw FormatException('Not a Groq duration', text);
  }
  final microseconds = parts.fold<double>(
    0,
    (total, part) =>
        total + double.parse(part[1]!) * _microsecondsPer(part[2]!),
  );
  return Duration(microseconds: microseconds.round());
}

int _microsecondsPer(String unit) => switch (unit) {
  'h' => Duration.microsecondsPerHour,
  'm' => Duration.microsecondsPerMinute,
  's' => Duration.microsecondsPerSecond,
  _ => Duration.microsecondsPerMillisecond,
};
