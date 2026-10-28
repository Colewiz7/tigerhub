/// Smart order for Today: Eat now rises at meal times, Up next in the hour
/// before an event. It decides what is shown first, never what is saved.
library;

import '../models/api_models.dart';
import 'dashboard.dart';

/// Campus minutes after midnight when Eat now rises: breakfast, lunch, dinner.
const List<(int, int)> mealWindows = [(7 * 60, 9 * 60 + 30), (11 * 60, 13 * 60 + 30), (17 * 60, 19 * 60 + 30)];

bool isMealTime(int wallMinute) => mealWindows.any((w) => wallMinute >= w.$1 && wallMinute < w.$2);

/// A timed event among [events] starts within the next hour of [now].
bool eventWithinHour(List<CampusEvent> events, DateTime now) {
  final soon = now.add(const Duration(hours: 1));
  return events.any((e) => !e.allDay && !e.startsAt.isBefore(now) && !e.startsAt.isAfter(soon));
}

/// [cards] in display order. Up next goes first when [eventSoon], Eat now
/// first at a meal time, Up next above Eat now when both apply. Only the
/// first card of each type moves; the rest keep their saved places.
List<CardInstance> smartOrder(List<CardInstance> cards, {required int wallMinute, required bool eventSoon}) {
  CardInstance? first(ModuleType type) => cards.where((c) => c.type == type).firstOrNull;
  final lifted = [
    if (eventSoon) ?first(ModuleType.generalEvents),
    if (isMealTime(wallMinute)) ?first(ModuleType.diningStatus),
  ];
  return [...lifted, for (final card in cards) if (!lifted.contains(card)) card];
}
