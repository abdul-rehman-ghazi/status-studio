/// Clip time as `m:ss.t`, or `h:mm:ss.t` from one hour up.
String formatClipTime(Duration time) {
  final tenths = (time.inMilliseconds ~/ 100) % 10;
  return '${_clockFace(time)}.$tenths';
}

/// Line timestamp as `m:ss`, or `h:mm:ss` from one hour up.
String formatTimestamp(Duration time) => _clockFace(time);

/// Length in seconds with one decimal, e.g. `18.5 s`.
String formatSeconds(Duration length) {
  final seconds = length.inMilliseconds / Duration.millisecondsPerSecond;
  return '${seconds.toStringAsFixed(1)} s';
}

const _shortMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// A date as `d MMM`, e.g. `7 Oct`.
String formatDayMonth(DateTime date) =>
    '${date.day} ${_shortMonths[date.month - 1]}';

String _clockFace(Duration time) {
  final seconds = _twoDigits(time.inSeconds % 60);
  if (time.inHours == 0) {
    return '${time.inMinutes}:$seconds';
  }
  final minutes = _twoDigits(time.inMinutes % 60);
  return '${time.inHours}:$minutes:$seconds';
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');
