/// Groq's free plan for `whisper-large-v3` (§12 M43–M47 design). Groq
/// sends no audio figures in its replies (§10 item 5, checked again in
/// M55), so the app counts against these.
const freeHourlyAudio = Duration(hours: 2);
const freeDailyAudio = Duration(hours: 8);

/// Groq bills a shorter request as this much audio.
const shortestBilledAudio = Duration(seconds: 10);

/// What the script pipeline tells about each piece it sends to Groq.
abstract interface class GroqUsageRecorder {
  Future<void> audioSent(Duration audio);

  /// Groq refused a piece for its limit and said to wait [wait].
  Future<void> limitReached(Duration wait);
}

/// One piece of audio Groq wrote a script for.
class AudioSend {
  const AudioSend({required this.sentAt, required this.audio});

  factory AudioSend.fromJson(Map<String, Object?> json) => AudioSend(
    sentAt: DateTime.parse(json['sentAt']! as String),
    audio: Duration(milliseconds: json['audioMs']! as int),
  );

  final DateTime sentAt;
  final Duration audio;

  Map<String, Object?> toJson() => {
    'sentAt': sentAt.toIso8601String(),
    'audioMs': audio.inMilliseconds,
  };
}

/// Which allowance runs out first.
enum AllowancePeriod { hour, day }

/// What is left of the allowance that runs out first.
class AudioLeft {
  const AudioLeft({required this.left, required this.period});

  final Duration left;
  final AllowancePeriod period;
}

/// The audio this phone sent to Groq with the saved key in the last day,
/// and how long Groq last said to wait (spec FR-45).
class GroqUsage {
  const GroqUsage({required this.sends, this.blockedUntil});

  factory GroqUsage.fromJson(Map<String, Object?> json) => GroqUsage(
    sends: [
      for (final send in json['sends']! as List<Object?>)
        AudioSend.fromJson(send! as Map<String, Object?>),
    ],
    blockedUntil: switch (json['blockedUntil']) {
      final String time => DateTime.parse(time),
      _ => null,
    },
  );

  static const none = GroqUsage(sends: []);

  final List<AudioSend> sends;

  /// Set when Groq refused a piece for its limit and gave a wait.
  final DateTime? blockedUntil;

  bool isBlockedAt(DateTime now) => blockedUntil?.isAfter(now) ?? false;

  Duration leftThisHourAt(DateTime now) =>
      _leftOf(freeHourlyAudio, const Duration(hours: 1), now);

  Duration leftTodayAt(DateTime now) =>
      _leftOf(freeDailyAudio, const Duration(days: 1), now);

  AudioLeft firstToRunOutAt(DateTime now) {
    final hour = leftThisHourAt(now);
    final day = leftTodayAt(now);
    return day < hour
        ? AudioLeft(left: day, period: AllowancePeriod.day)
        : AudioLeft(left: hour, period: AllowancePeriod.hour);
  }

  /// Sends older than a day no longer count, so they are dropped.
  GroqUsage withSend(AudioSend send) {
    final dayAgo = send.sentAt.subtract(const Duration(days: 1));
    return GroqUsage(
      sends: [
        for (final earlier in sends)
          if (earlier.sentAt.isAfter(dayAgo)) earlier,
        send,
      ],
      blockedUntil: blockedUntil,
    );
  }

  GroqUsage blockedAfter(Duration wait, DateTime now) =>
      GroqUsage(sends: sends, blockedUntil: now.add(wait));

  Map<String, Object?> toJson() => {
    'sends': [for (final send in sends) send.toJson()],
    'blockedUntil': ?blockedUntil?.toIso8601String(),
  };

  Duration _leftOf(Duration allowance, Duration window, DateTime now) {
    if (isBlockedAt(now)) {
      return Duration.zero;
    }
    final since = now.subtract(window);
    final used = sends
        .where((send) => send.sentAt.isAfter(since))
        .fold(Duration.zero, (total, send) => total + send.audio);
    return used >= allowance ? Duration.zero : allowance - used;
  }
}
