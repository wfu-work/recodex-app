import '../models/bridge_models.dart';

/// Codex's `last` includes input (including cached input) and output. Neither
/// a turn total nor a thread total measures the currently occupied context.
ContextWindowUsage? readContextWindowUsage(Map<String, dynamic> data) {
  for (final value in [
    data['tokenUsage'],
    data['token_usage'],
    data['info'],
    data,
  ]) {
    if (value is! Map) continue;
    final limit = value['modelContextWindow'] ?? value['model_context_window'];
    final last = value['last'] ?? value['last_token_usage'];
    if (last is! Map || limit is! int || limit <= 0) continue;
    var used = last['totalTokens'] ?? last['total_tokens'];
    if (used == null) {
      final input = last['inputTokens'] ?? last['input_tokens'];
      final output = last['outputTokens'] ?? last['output_tokens'];
      if (input is int && input >= 0 && output is int && output >= 0) {
        used = input + output;
      }
    }
    if (used is! int || used < 0) continue;
    return ContextWindowUsage(
      usedTokens: used,
      maxTokens: limit,
      updatedAt: DateTime.tryParse(value['updatedAt']?.toString() ?? ''),
    );
  }
  return null;
}

ContextWindowUsage? newerContextWindowUsage(
  ContextWindowUsage? current,
  ContextWindowUsage? incoming,
) {
  if (incoming == null) return current;
  if (current?.updatedAt != null &&
      incoming.updatedAt != null &&
      current!.updatedAt!.isAfter(incoming.updatedAt!)) {
    return current;
  }
  return incoming;
}

/// Events are ordered by turn, including late metadata inserted into an older
/// answer. Compare sample times within a turn so a stale completion/history
/// snapshot cannot overwrite a newer (possibly smaller, compacted) context.
ContextWindowUsage? latestContextWindowUsage(Iterable<SessionEvent> events) {
  final turns = <String?, ContextWindowUsage?>{};
  for (final event in events) {
    if (event.contextWindowUsage == null) continue;
    turns[event.turnId] = newerContextWindowUsage(
      turns[event.turnId],
      event.contextWindowUsage,
    );
  }
  return turns.isEmpty ? null : turns.values.last;
}
