import '../models/bridge_models.dart';
import 'answer_metadata.dart';

/// One completed turn, keyed by host scope + thread + turn in storage.
/// Cached input is a subset of input; reasoning is a subset of output.
class AnswerUsageRecord {
  const AnswerUsageRecord({
    required this.threadId,
    required this.turnId,
    required this.title,
    required this.workspace,
    this.usage,
    this.completedAt,
    this.durationMs,
  });

  final String threadId;
  final String turnId;
  final String title;
  final String workspace;
  final TokenUsage? usage;
  final DateTime? completedAt;
  final int? durationMs;

  String get key => '$threadId\u0000$turnId';
  DateTime? get day => completedAt == null ? null : usageDay(completedAt!);

  AnswerUsageRecord merge(AnswerUsageRecord incoming) => AnswerUsageRecord(
    threadId: threadId,
    turnId: turnId,
    title: incoming.title.isEmpty ? title : incoming.title,
    workspace: incoming.workspace.isEmpty ? workspace : incoming.workspace,
    usage: incoming.usage ?? usage,
    completedAt: incoming.completedAt ?? completedAt,
    durationMs: incoming.durationMs ?? durationMs,
  );

  Map<String, dynamic> toJson() => {
    'threadId': threadId,
    'turnId': turnId,
    'title': title,
    'workspace': workspace,
    if (usage != null) 'usage': usage!.toJson(),
    if (completedAt != null)
      'completedAt': completedAt!.toUtc().toIso8601String(),
    if (durationMs != null) 'durationMs': durationMs,
  };

  factory AnswerUsageRecord.fromJson(Map<String, dynamic> json) =>
      AnswerUsageRecord(
        threadId: json['threadId'] as String,
        turnId: json['turnId'] as String,
        title: json['title'] as String? ?? '',
        workspace: json['workspace'] as String? ?? '',
        usage: json['usage'] is Map
            ? TokenUsage.fromJson(
                Map<String, dynamic>.from(json['usage'] as Map),
              )
            : null,
        completedAt: DateTime.tryParse(json['completedAt'] as String? ?? ''),
        durationMs: json['durationMs'] as int?,
      );
}

List<AnswerUsageRecord> collectAnswerUsage(
  String threadId,
  List<SessionEvent> events, {
  SessionRecord? session,
}) {
  final turns = <String, List<SessionEvent>>{};
  for (final event in events) {
    final id = event.turnId;
    if (id == null || id.isEmpty) continue;
    (turns[id] ??= []).add(event);
  }
  final result = <AnswerUsageRecord>[];
  var previous = const <SessionEvent>[];
  for (final entry in turns.entries) {
    final current = entry.value;
    final completed = current.any(
      (event) =>
          event.completedAt != null ||
          const [
            'done',
            'completed',
            'interrupted',
            'error',
          ].contains(event.kind),
    );
    if (completed) {
      result.add(
        AnswerUsageRecord(
          threadId: threadId,
          turnId: entry.key,
          title: session?.displayTitle ?? '',
          workspace: session?.workspace ?? '',
          usage: answerTokenUsage(current, previousAnswerEvents: previous),
          completedAt: answerCompletedAt(current),
          durationMs: current.reversed
              .map((event) => event.durationMs)
              .whereType<int>()
              .where((value) => value >= 0)
              .firstOrNull,
        ),
      );
    }
    previous = current;
  }
  return result;
}

/// Calendar arithmetic (rather than 24-hour durations) also works across DST.
DateTime usageDay(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

DateTime shiftUsageDay(DateTime day, int offset) =>
    DateTime(day.year, day.month, day.day + offset);

class UsageTotals {
  UsageTotals(Iterable<AnswerUsageRecord> records) {
    for (final record in records) {
      answerCount++;
      final usage = record.usage;
      if (usage == null || usage.scope != TokenUsageScope.turn) {
        missingCount++;
        continue;
      }
      measuredCount++;
      totalTokens += usage.totalTokens;
      if (usage.hasBreakdown) {
        breakdownCount++;
        inputTokens += usage.inputTokens;
        outputTokens += usage.outputTokens;
      }
      if (usage.cachedInputTokens != null) {
        cachedCount++;
        cachedInputTokens += usage.cachedInputTokens!;
      }
    }
  }

  int answerCount = 0;
  int measuredCount = 0;
  int missingCount = 0;
  int breakdownCount = 0;
  int cachedCount = 0;
  int totalTokens = 0;
  int inputTokens = 0;
  int outputTokens = 0;
  int cachedInputTokens = 0;
}

Map<DateTime, UsageTotals> dailyUsageTotals(
  Iterable<AnswerUsageRecord> records,
) {
  final grouped = <DateTime, List<AnswerUsageRecord>>{};
  for (final record in records) {
    final day = record.day;
    if (day != null) (grouped[day] ??= []).add(record);
  }
  return grouped.map((day, records) => MapEntry(day, UsageTotals(records)));
}

int usageHeatLevel(int tokens, int maxTokens) {
  if (tokens <= 0 || maxTokens <= 0) return 0;
  return (tokens * 4 / maxTokens).ceil().clamp(1, 4);
}

String usageDateLabel(DateTime value) {
  final date = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${date.year}/${two(date.month)}/${two(date.day)}';
}
