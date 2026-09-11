import '../models/bridge_models.dart';

/// Keep replayed/cached items beside their own turn without sorting by receipt
/// time (a replay's receipt time is newer than the conversation it belongs to).
List<SessionEvent> orderTimelineEvents(Iterable<SessionEvent> events) {
  final groups = <List<SessionEvent>>[];
  final turns = <String, List<SessionEvent>>{};
  List<SessionEvent>? current;
  for (final event in events) {
    final turnId = event.turnId?.trim() ?? '';
    if (turnId.isNotEmpty) {
      final group = turns.putIfAbsent(turnId, () {
        final group = <SessionEvent>[];
        groups.add(group);
        return group;
      });
      group.add(event);
      // A late old-turn item must not move subsequent legacy/unscoped
      // activity away from the latest prompt.
      if (identical(group, groups.last)) current = group;
      continue;
    } else if (current == null || event.kind == 'user') {
      current = <SessionEvent>[];
      groups.add(current);
    }
    current.add(event);
  }
  return groups.expand((group) => group).toList();
}

/// Insert late items before the turn's completion, never after a newer prompt.
void insertEventInTurn(List<SessionEvent> events, SessionEvent event) {
  final turnId = event.turnId?.trim() ?? '';
  if (turnId.isEmpty) {
    events.add(event);
    return;
  }
  final last = events.lastIndexWhere((item) => item.turnId == turnId);
  if (last < 0) {
    events.add(event);
    return;
  }
  var index = last + 1;
  while (index > 0 &&
      events[index - 1].turnId == turnId &&
      (events[index - 1].kind == 'done' ||
          events[index - 1].kind == 'token_usage')) {
    index--;
  }
  events.insert(index, event);
}
