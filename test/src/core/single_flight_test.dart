import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/core/single_flight.dart';

void main() {
  test('concurrent_runs_with_same_key_share_one_call', () async {
    final flights = SingleFlight<int>();
    final release = Completer<void>();
    var calls = 0;
    Future<int> work() async {
      calls++;
      await release.future;
      return 7;
    }

    final first = flights.run('a', work);
    final second = flights.run('a', work);
    release.complete();
    await Future.wait([first, second]);

    expect(calls, 1);
  });

  test('a_finished_run_can_run_again', () async {
    final flights = SingleFlight<int>();
    var calls = 0;
    Future<int> work() async => ++calls;

    await flights.run('a', work);
    await flights.run('a', work);

    expect(calls, 2);
  });

  test('a_failed_run_can_run_again', () async {
    final flights = SingleFlight<int>();
    var calls = 0;
    Future<int> work() async {
      calls++;
      if (calls == 1) {
        throw StateError('first fails');
      }
      return calls;
    }

    await expectLater(flights.run('a', work), throwsStateError);
    await flights.run('a', work);

    expect(calls, 2);
  });
}
