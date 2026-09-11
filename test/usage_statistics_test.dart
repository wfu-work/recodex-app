import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:recodex/app/models/bridge_models.dart';
import 'package:recodex/app/services/session_cache.dart';
import 'package:recodex/app/services/session_cache_backend.dart';
import 'package:recodex/app/services/usage_statistics.dart';

SessionCacheScope scope(String id) => SessionCacheScope(
  key: id,
  pairingId: id,
  spaceId: 'space',
  endpointId: 'app',
  targetDeviceId: id,
);

List<SessionEvent> answer(String turn, int tokens, {DateTime? end}) => [
  SessionEvent(kind: 'assistant', text: 'answer', turnId: turn),
  SessionEvent(
    kind: 'done',
    text: '',
    turnId: turn,
    itemId: 'turn-end:$turn',
    completedAt: end,
    durationMs: 1000,
    usage: TokenUsage(
      inputTokens: tokens - 10,
      outputTokens: 10,
      totalTokens: tokens,
      cachedInputTokens: 30,
      scope: TokenUsageScope.turn,
    ),
  ),
];

void main() {
  test(
    'ledger replaces repeated/corrected snapshots and survives pruning/reopening',
    () async {
      final backend = MemorySessionCacheBackend();
      var cache = SessionCache(backend: backend);
      final host = scope('host');
      await cache.saveTimeline(host, 'thread', answer('a', 100));
      await cache.saveTimelineIncremental(host, 'thread', answer('a', 100));
      expect((await cache.loadUsage(host)).single.usage?.totalTokens, 100);
      await cache.saveTimelineIncremental(host, 'thread', answer('a', 80));
      await cache.saveTimeline(host, 'thread', answer('b', 200));
      await cache.close();
      cache = SessionCache(backend: backend);
      addTearDown(cache.close);
      final records = await cache.loadUsage(host);
      expect(records, hasLength(2));
      expect(UsageTotals(records).totalTokens, 280);
      expect(UsageTotals(records).cachedInputTokens, 60);
      expect(
        (await cache.loadTimeline(
          host,
          'thread',
        )).every((event) => event.turnId == 'b'),
        isTrue,
      );
    },
  );

  test('persists statistics before the 500-event timeline limit', () async {
    final cache = SessionCache(backend: MemorySessionCacheBackend());
    addTearDown(cache.close);
    await cache.saveTimeline(scope('host'), 'thread', [
      for (var i = 0; i < 300; i++) ...answer('$i', 100),
    ]);
    expect(await cache.loadTimeline(scope('host'), 'thread'), hasLength(500));
    expect(await cache.loadUsage(scope('host')), hasLength(300));
  });

  test('same thread and turn IDs remain isolated across hosts', () async {
    final cache = SessionCache(backend: MemorySessionCacheBackend());
    addTearDown(cache.close);
    await cache.saveTimeline(scope('first'), 'thread', answer('a', 100));
    await cache.saveTimeline(scope('second'), 'thread', answer('a', 200));
    expect(
      (await cache.loadUsage(scope('first'))).single.usage?.totalTokens,
      100,
    );
    expect(
      (await cache.loadUsage(scope('second'))).single.usage?.totalTokens,
      200,
    );
  });

  test(
    'backfills old cached timelines and keeps metadata across incomplete refreshes',
    () async {
      final backend = MemorySessionCacheBackend();
      final cache = SessionCache(backend: backend);
      addTearDown(cache.close);
      final original = answer('a', 100, end: DateTime(2026, 9, 10, 23, 59));
      await backend.replaceTimeline('host', 'thread', [
        for (var i = 0; i < original.length; i++)
          SessionCacheTimelineItem(
            key: '$i',
            ordinal: i,
            payload: jsonEncode(original[i].toJson()),
          ),
      ]);
      expect(
        (await cache.loadUsage(scope('host'))).single.usage?.totalTokens,
        100,
      );
      await cache.saveTimeline(scope('host'), 'thread', [
        const SessionEvent(kind: 'done', text: '', turnId: 'a'),
      ]);
      final restored = (await cache.loadUsage(scope('host'))).single;
      expect(restored.usage?.totalTokens, 100);
      expect(restored.day, DateTime(2026, 9, 10));
      expect(restored.durationMs, 1000);
    },
  );

  test(
    'ongoing calls are excluded; missing usage and dates are not fabricated',
    () {
      final records = collectAnswerUsage('thread', [
        ...answer('a', 100),
        const SessionEvent(kind: 'done', text: '', turnId: 'missing'),
        SessionEvent(
          kind: 'token_usage',
          text: '',
          turnId: 'running',
          usage: answer('a', 200).last.usage,
        ),
      ]);
      expect(records, hasLength(2));
      expect(records.first.completedAt, isNull);
      expect(records.last.usage, isNull);
      expect(UsageTotals(records).totalTokens, 100);
      expect(UsageTotals(records).missingCount, 1);
      expect(dailyUsageTotals(records), isEmpty);
    },
  );

  test(
    'daily totals use local completion dates, including leap and month boundaries',
    () {
      final records = [
        ...collectAnswerUsage(
          'thread',
          answer('a', 100, end: DateTime(2024, 2, 29, 23, 59)),
        ),
        ...collectAnswerUsage(
          'thread',
          answer('b', 200, end: DateTime(2024, 3, 1)),
        ),
      ];
      final days = dailyUsageTotals(records);
      expect(days[DateTime(2024, 2, 29)]?.totalTokens, 100);
      expect(days[DateTime(2024, 3, 1)]?.totalTokens, 200);
      expect(shiftUsageDay(DateTime(2024, 3, 1), -1), DateTime(2024, 2, 29));
      expect(usageHeatLevel(0, 200), 0);
      expect(usageHeatLevel(1, 200), 1);
      expect(usageHeatLevel(100, 200), 2);
      expect(usageHeatLevel(200, 200), 4);
      expect(usageHeatLevel(0, 0), 0);
    },
  );

  test('cumulative snapshots are differenced once per completed answer', () {
    SessionEvent total(String turn, int count) => SessionEvent(
      kind: 'done',
      text: '',
      turnId: turn,
      usage: TokenUsage(
        inputTokens: count,
        outputTokens: 10,
        totalTokens: count + 10,
        scope: TokenUsageScope.thread,
      ),
    );
    final records = collectAnswerUsage('thread', [
      total('a', 1000),
      total('b', 4000),
      total('b', 4000),
    ]);
    expect(records.first.usage, isNull);
    expect(records.last.usage?.totalTokens, 3000);
    expect(UsageTotals(records).totalTokens, 3000);
  });
}
