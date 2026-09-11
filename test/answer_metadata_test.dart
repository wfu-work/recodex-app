import 'package:flutter_test/flutter_test.dart';
import 'package:recodex/app/models/bridge_models.dart';
import 'package:recodex/app/services/answer_metadata.dart';

void main() {
  test('abbreviates consumption without losing unit boundaries', () {
    final cases = {
      0: '0',
      999: '999',
      1000: '1K',
      1234: '1.23K',
      10000: '10K',
      21935: '21.94K',
      999994: '999.99K',
      999999: '1M',
      1000000: '1M',
      2391870: '2.39M',
      999999999: '1B',
      123456789012: '123.46B',
      1000000000000: '1T',
    };
    for (final entry in cases.entries) {
      expect(
        formatCompactTokenCount(entry.key),
        entry.value,
        reason: '${entry.key}',
      );
    }
    expect(formatTokenCount(2391870), '2,391,870');
  });
  test(
    'reads Relay turn usage before cumulative counters and caches its breakdown',
    () {
      final usage = readTokenUsage({
        'turnUsage': {
          'inputTokens': 276669,
          'outputTokens': 3902,
          'totalTokens': 280571,
          'cachedInputTokens': 175232,
          'reasoningOutputTokens': 2129,
        },
        'tokenUsage': {
          'total': {
            'inputTokens': 9055152,
            'outputTokens': 79770,
            'totalTokens': 9134922,
          },
        },
      });
      expect(usage?.scope, TokenUsageScope.turn);
      expect(usage?.totalTokens, 280571);
      expect(usage?.cachedInputTokens, 175232);
      expect(usage?.reasoningOutputTokens, 2129);
      final cached = TokenUsage.fromJson(usage!.toJson());
      expect(cached.cachedInputTokens, 175232);
      expect(cached.reasoningOutputTokens, 2129);
      expect(cached.totalTokens, 280571);
    },
  );
  test('distinguishes turn usage from thread totals and last model call', () {
    final thread = readTokenUsage({
      'tokenUsage': {
        'total': {
          'inputTokens': 8000,
          'outputTokens': 2000,
          'totalTokens': 10000,
        },
        'last': {'inputTokens': 80, 'outputTokens': 20, 'totalTokens': 100},
      },
    }, scope: TokenUsageScope.turn);
    expect(thread?.scope, TokenUsageScope.thread);
    expect(thread?.totalTokens, 10000);
    expect(tokenUsageLabel(thread), '会话累计消耗 · 总 10K');
    final turn = readTokenUsage({
      'usage': {'input_tokens': 120, 'output_tokens': 30},
    }, scope: TokenUsageScope.turn);
    expect(turn?.scope, TokenUsageScope.turn);
    expect(turn?.totalTokens, 150);
    final last = readTokenUsage({
      'tokenUsage': {
        'last': {'totalTokens': 50},
      },
    });
    expect(last?.scope, TokenUsageScope.lastCall);
    expect(last?.hasBreakdown, isFalse);
  });

  test('repeated or corrected snapshots are replaced without summing', () {
    SessionEvent usage(int total) => SessionEvent(
      kind: 'token_usage',
      text: '',
      usage: TokenUsage(
        inputTokens: total - 10,
        outputTokens: 10,
        totalTokens: total,
        scope: TokenUsageScope.turn,
      ),
    );
    expect(answerTokenUsage([usage(100), usage(100)])?.totalTokens, 100);
    expect(
      answerTokenUsage([usage(100), usage(80), usage(80)])?.totalTokens,
      80,
    );
    expect(answerTokenUsage([usage(80), usage(100)])?.totalTokens, 100);
  });

  test('prefers explicit turn usage over a later cumulative notification', () {
    final usage = answerTokenUsage([
      SessionEvent(
        kind: 'done',
        text: '',
        usage: readTokenUsage({
          'turnUsage': {'totalTokens': 150},
        }),
      ),
      SessionEvent(
        kind: 'token_usage',
        text: '',
        usage: readTokenUsage({
          'tokenUsage': {
            'total': {'totalTokens': 10000},
          },
        }),
      ),
    ]);
    expect(usage?.totalTokens, 150);
    expect(usage?.scope, TokenUsageScope.turn);
  });

  SessionEvent cumulative(
    String turnId,
    int input,
    int output, {
    int? cached,
    int? reasoning,
  }) => SessionEvent(
    kind: 'token_usage',
    text: '',
    turnId: turnId,
    usage: TokenUsage(
      inputTokens: input,
      outputTokens: output,
      totalTokens: input + output,
      cachedInputTokens: cached,
      reasoningOutputTokens: reasoning,
      scope: TokenUsageScope.thread,
    ),
  );
  final previousAnswer = [
    cumulative('a', 8000, 2000, cached: 6000, reasoning: 1000),
    const SessionEvent(kind: 'done', text: '', turnId: 'a'),
  ];

  test('derives all calls in the answer without adding repeated snapshots', () {
    final events = [
      cumulative('b', 9000, 2100, cached: 6700, reasoning: 1050),
      cumulative('b', 12000, 2500, cached: 9000, reasoning: 1200),
      cumulative('b', 12000, 2500, cached: 9000, reasoning: 1200),
    ];
    final usage = answerTokenUsage(
      events,
      previousAnswerEvents: previousAnswer,
    )!;
    expect(usage.scope, TokenUsageScope.turn);
    expect(usage.totalTokens, 4500);
    expect(usage.inputTokens, 4000);
    expect(usage.outputTokens, 500);
    expect(usage.cachedInputTokens, 3000);
    expect(usage.reasoningOutputTokens, 200);
    expect(tokenUsageLabel(usage), '本次回答消耗 · 总 4.5K');
    final restored = events
        .map((event) => SessionEvent.fromJson(event.toJson(cacheSafe: true)))
        .toList();
    expect(
      answerTokenUsage(
        restored,
        previousAnswerEvents: previousAnswer,
      )?.totalTokens,
      4500,
    );
  });

  test('does not substitute cumulative, last-call or unscoped usage', () {
    for (final scope in [
      TokenUsageScope.thread,
      TokenUsageScope.lastCall,
      TokenUsageScope.unknown,
    ]) {
      final events = [
        SessionEvent(
          kind: 'done',
          text: '',
          turnId: 'b',
          usage: TokenUsage(
            inputTokens: 12000,
            outputTokens: 2500,
            totalTokens: 14500,
            scope: scope,
          ),
        ),
      ];
      expect(answerTokenUsage(events), isNull);
    }
  });

  test('rejects missing, unfinished, ambiguous and same-turn baselines', () {
    final current = [cumulative('b', 12000, 2500)];
    for (final previous in <List<SessionEvent>>[
      [],
      [cumulative('a', 8000, 2000)],
      [const SessionEvent(kind: 'done', text: '', turnId: 'a')],
      [
        cumulative('b', 8000, 2000),
        const SessionEvent(kind: 'done', text: '', turnId: 'b'),
      ],
      [...previousAnswer, cumulative('other', 8500, 2100)],
      [
        cumulative('a', 8000, 2000).copyWith(turnId: ''),
        const SessionEvent(kind: 'done', text: ''),
      ],
    ]) {
      expect(answerTokenUsage(current, previousAnswerEvents: previous), isNull);
    }
  });

  test('counter resets invalidate a turn even after counters recover', () {
    for (final samples in [
      [cumulative('b', 100, 10)],
      [cumulative('b', 9000, 1900)],
      [
        cumulative('b', 12000, 2500),
        cumulative('b', 100, 10),
        cumulative('b', 15000, 3000),
      ],
    ]) {
      expect(
        answerTokenUsage(samples, previousAnswerEvents: previousAnswer),
        isNull,
      );
    }
  });

  test(
    'missing optional breakdowns remain unavailable and zero stays valid',
    () {
      final usage = answerTokenUsage([
        cumulative('b', 8000, 2000),
      ], previousAnswerEvents: previousAnswer)!;
      expect(usage.totalTokens, 0);
      expect(usage.cachedInputTokens, isNull);
      expect(usage.reasoningOutputTokens, isNull);
      final totalOnly = answerTokenUsage([
        SessionEvent(
          kind: 'done',
          text: '',
          turnId: 'b',
          usage: readTokenUsage({
            'tokenUsage': {
              'total': {'totalTokens': 14500},
            },
          }),
        ),
      ], previousAnswerEvents: previousAnswer)!;
      expect(totalOnly.totalTokens, 4500);
      expect(totalOnly.hasBreakdown, isFalse);
    },
  );

  test(
    'missing statistics and item timestamps do not fabricate completion',
    () {
      expect(readTokenUsage({'usage': {}}), isNull);
      expect(
        readTokenUsage({
          'usage': {'totalTokens': -1},
        }),
        isNull,
      );
      expect(answerTokenUsage([]), isNull);
      expect(
        answerCompletedAt([
          SessionEvent(
            kind: 'assistant',
            text: '回答',
            time: DateTime(2026, 9, 10),
          ),
        ]),
        isNull,
      );
    },
  );

  test('completion and token scope survive caching and late usage updates', () {
    final end = DateTime.utc(2026, 9, 10, 9, 10, 11);
    final terminal = SessionEvent(
      kind: 'done',
      text: '',
      time: end,
      completedAt: end,
      durationMs: 2000,
      turnId: 'turn-a',
      itemId: 'turn-end:turn-a',
      usage: readTokenUsage({
        'usage': {'totalTokens': 100},
      }, scope: TokenUsageScope.turn),
    );
    final restored = SessionEvent.fromJson(terminal.toJson(cacheSafe: true));
    expect(restored.completedAt, end);
    expect(restored.usage?.scope, TokenUsageScope.turn);
    expect(restored.usage?.hasBreakdown, isFalse);
    expect(restored.copyWith(text: 'done').completedAt, end);
    expect(
      answerCompletedAt([
        restored,
        SessionEvent(
          kind: 'token_usage',
          text: '',
          time: end.add(const Duration(hours: 1)),
        ),
      ]),
      end,
    );
  });

  test(
    'late metrics remain within their original answer on history refresh',
    () {
      final events = [
        const SessionEvent(kind: 'user', text: '第一问', turnId: 'a'),
        const SessionEvent(kind: 'assistant', text: '第一答', turnId: 'a'),
        const SessionEvent(kind: 'user', text: '第二问', turnId: 'b'),
        const SessionEvent(kind: 'assistant', text: '第二答', turnId: 'b'),
      ];
      const metric = SessionEvent(kind: 'token_usage', text: '', turnId: 'a');
      insertAnswerMetadata(events, metric);
      expect(events.indexOf(metric), 2);
      insertAnswerMetadata(
        events,
        const SessionEvent(kind: 'done', text: '', turnId: 'missing'),
      );
      insertAnswerMetadata(
        events,
        const SessionEvent(kind: 'token_usage', text: ''),
      );
      expect(events.length, 5);
      expect(events.last.text, '第二答');
    },
  );
}
