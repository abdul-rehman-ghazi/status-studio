import 'dart:async';

import 'package:flutter/animation.dart';

/// Completes once [animation] (a covered route's secondary animation) has
/// finished sliding back, so what the covering screen needed is free again.
/// A route that never finishes sliding is waited for one second only.
Future<void> untilDismissed(Animation<double>? animation) async {
  if (animation == null || animation.isDismissed) {
    return;
  }
  final dismissed = Completer<void>();
  void onStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && !dismissed.isCompleted) {
      dismissed.complete();
    }
  }

  animation.addStatusListener(onStatus);
  try {
    await dismissed.future.timeout(const Duration(seconds: 1));
  } on TimeoutException {
    // A route that never finishes sliding must not leave a blank player.
  } finally {
    animation.removeStatusListener(onStatus);
  }
}
