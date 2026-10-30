/// [time] as FFmpeg seconds with millisecond precision, e.g. `53.500`.
String ffmpegSeconds(Duration time) =>
    (time.inMicroseconds / Duration.microsecondsPerSecond).toStringAsFixed(3);
