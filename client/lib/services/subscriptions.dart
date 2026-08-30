/// A bag of stream subscriptions that get cancelled together.
///
/// Every screen in this app reads its data by listening to a stream that emits
/// twice: once from cache, once from the refresh behind it. Fourteen call sites
/// did that and none of them kept the subscription, so none of them could
/// cancel it. That leaked in two directions at once.
///
/// **The refresh ticker.** It fires every two minutes and re-subscribed four
/// streams each time, so after an hour the shell had well over a hundred live
/// subscriptions, all still calling `setState`.
///
/// **Navigation.** Opening the Campus tab subscribes six streams in
/// `initState`. Leaving and returning made six more, and the old ones stayed
/// alive.
///
/// The leak was not the visible symptom. Stale subscriptions kept delivering,
/// so an older result could land after a newer one and overwrite it, and the
/// screen would show data from a previous visit or flicker between the two.
/// That is what "glitches out when switching pages" was.
///
/// Usage: hold one per State, `add` every subscription, `cancelAll` before
/// re-subscribing, and `dispose` in the State's own dispose.
library;

import 'dart:async';

class Subscriptions {
  final List<StreamSubscription<dynamic>> _held = [];

  /// Whether anything is currently held. Useful in tests.
  int get length => _held.length;

  void add(StreamSubscription<dynamic> subscription) =>
      _held.add(subscription);

  /// Cancel everything held so far and start again.
  ///
  /// Called before a refresh re-subscribes, so a tick replaces its
  /// predecessors rather than stacking on them.
  void cancelAll() {
    for (final subscription in _held) {
      subscription.cancel();
    }
    _held.clear();
  }

  /// Same thing, named for where it belongs: a State's dispose.
  void dispose() => cancelAll();
}
