import '../models/bridge_models.dart';

/// Usage notifications are snapshots, not deltas. Preserve their scope so a
/// thread total (or one model call) is never presented as a turn's consumption.
TokenUsage? readTokenUsage(
  Map<String, dynamic> data, {
  TokenUsageScope scope = TokenUsageScope.unknown,
}) {
  Map<String, dynamic>? map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : null;
  int? number(Object? value) {
    final parsed = value is num && value.isFinite
        ? value.toInt()
        : int.tryParse(value?.toString() ?? '');
    return parsed != null && parsed >= 0 ? parsed : null;
  }

  TokenUsage? parse(Object? value, TokenUsageScope valueScope) {
    final source = map(value);
    if (source == null) return null;
    final input = number(
      source['inputTokens'] ??
          source['input_tokens'] ??
          source['promptTokens'] ??
          source['prompt_tokens'],
    );
    final output = number(
      source['outputTokens'] ??
          source['output_tokens'] ??
          source['completionTokens'] ??
          source['completion_tokens'],
    );
    final total = number(
      source['totalTokens'] ?? source['total_tokens'] ?? source['total'],
    );
    if (input == null && output == null && total == null) return null;
    return TokenUsage(
      inputTokens: input ?? 0,
      outputTokens: output ?? 0,
      totalTokens: total ?? (input ?? 0) + (output ?? 0),
      scope: valueScope,
      hasBreakdown: input != null && output != null,
      cachedInputTokens: number(
        source['cachedInputTokens'] ?? source['cached_input_tokens'],
      ),
      reasoningOutputTokens: number(
        source['reasoningOutputTokens'] ?? source['reasoning_output_tokens'],
      ),
    );
  }

  final turn = parse(
    data['turnUsage'] ?? data['turn_usage'],
    TokenUsageScope.turn,
  );
  if (turn != null) return turn;
  for (final candidate in [
    data['usage'],
    data['tokenUsage'],
    data['token_usage'],
    data['tokens'],
    data,
  ]) {
    final direct = parse(candidate, scope);
    if (direct != null) return direct;
    final nested = map(candidate);
    final total = parse(nested?['total'], TokenUsageScope.thread);
    if (total != null) return total;
    final last = parse(nested?['last'], TokenUsageScope.lastCall);
    if (last != null) return last;
  }
  return null;
}

TokenUsage? answerTokenUsage(List<SessionEvent> events) {
  final latest = <TokenUsageScope, TokenUsage>{};
  for (final event in events) {
    final usage = event.usage;
    if (usage != null) latest[usage.scope] = usage;
  }
  return latest[TokenUsageScope.turn] ??
      latest[TokenUsageScope.unknown] ??
      latest[TokenUsageScope.thread] ??
      latest[TokenUsageScope.lastCall];
}

DateTime? answerCompletedAt(List<SessionEvent> events) {
  for (final event in events.reversed) {
    if (event.completedAt != null) return event.completedAt;
  }
  // Compatibility with cached terminal markers from earlier app versions.
  for (final event in events.reversed) {
    if (const [
          'done',
          'completed',
          'interrupted',
          'error',
        ].contains(event.kind) &&
        event.time != null) {
      return event.time;
    }
  }
  // Older thread.read projections stored the turn end and measured duration
  // together on the last item. A plain item timestamp alone is not an end time.
  for (final event in events.reversed) {
    if (event.durationMs != null &&
        event.durationMs! >= 0 &&
        event.time != null) {
      return event.time;
    }
  }
  return null;
}

String tokenUsageLabel(TokenUsage? usage) {
  if (usage == null) return '消耗 未提供';
  final prefix = switch (usage.scope) {
    TokenUsageScope.thread => '会话累计消耗',
    TokenUsageScope.lastCall => '最近调用消耗',
    _ => '消耗',
  };
  return '$prefix · 总 ${formatCompactTokenCount(usage.totalTokens)}';
}

/// Use at most two decimals in the transcript; tooltips retain exact counts.
String formatCompactTokenCount(int value) {
  if (value.abs() < 1000) return value.toString();
  const units = ['', 'K', 'M', 'B', 'T'];
  var scaled = value.abs().toDouble();
  var unit = 0;
  while (scaled >= 1000 && unit < units.length - 1) {
    scaled /= 1000;
    unit++;
  }
  // Rounding a value such as 999,999 should produce 1M, not 1000K.
  scaled = (scaled * 100).round() / 100;
  if (scaled >= 1000 && unit < units.length - 1) {
    scaled /= 1000;
    unit++;
  }
  final number = scaled.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  return '${value < 0 ? '-' : ''}$number${units[unit]}';
}

String formatTokenCount(int value) => value.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
  (match) => '${match[1]},',
);

/// Keep late/cached statistics next to their own turn when history is replaced.
/// Unattributable legacy metrics are intentionally not moved to the last answer.
void insertAnswerMetadata(List<SessionEvent> events, SessionEvent event) {
  if (event.turnId == null) return;
  final index = events.lastIndexWhere((item) => item.turnId == event.turnId);
  if (index >= 0) events.insert(index + 1, event);
}
