/// Runs at most one piece of work per key at a time; callers asking for a
/// key that is already running share its result.
class SingleFlight<T> {
  final _running = <String, Future<T>>{};

  Future<T> run(String key, Future<T> Function() work) {
    final running = _running[key];
    if (running != null) {
      return running;
    }
    // A block body: returning the removed future would make whenComplete
    // wait on the very future it belongs to.
    final started = work().whenComplete(() {
      _running.remove(key);
    });
    _running[key] = started;
    return started;
  }
}
