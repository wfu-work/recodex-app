import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:recodex/app/models/bridge_models.dart';
import 'package:recodex/app/services/answer_metadata.dart';
import 'package:recodex/app/services/context_window_usage.dart';
import 'package:recodex/app/services/session_cache.dart';
import 'package:recodex/app/services/session_cache_backend.dart';

void main() {
  test(
    'reads recent context without adding cumulative or cached consumption',
    () {
      final payload = {
        'turnUsage': {'totalTokens': 280571},
        'tokenUsage': {
          'total': {'totalTokens': 9964237},
          'last': {
            'inputTokens': 207000,
            'outputTokens': 1000,
            'cachedInputTokens': 200000,
            'totalTokens': 208000,
          },
          'modelContextWindow': 258400,
          'updatedAt': '2026-09-10T12:00:00Z',
        },
      };
      final usage = readContextWindowUsage(payload)!;
      expect(usage.usedTokens, 208000);
      expect(usage.maxTokens, 258400);
      expect(usage.percent, 80);
      expect(readTokenUsage(payload)?.totalTokens, 280571);
      final event = SessionEvent(
        kind: 'done',
        text: '',
        contextWindowUsage: usage,
      );
      final restored = SessionEvent.fromJson(
        jsonDecode(jsonEncode(event.toJson())),
      );
      expect(restored.contextWindowUsage, usage);
      expect(restored.copyWith(text: 'answer').contextWindowUsage, usage);
    },
  );

  test('supports journal names and input/output fallback including zero', () {
    for (final input in [0, 207000]) {
      final usage = readContextWindowUsage({
        'info': {
          'last_token_usage': {'input_tokens': input, 'output_tokens': 0},
          'model_context_window': 258400,
        },
      });
      expect(usage?.usedTokens, input);
    }
  });

  test('missing, cumulative-only or invalid measurements remain unknown', () {
    for (final data in <Map<String, dynamic>>[
      {},
      {
        'modelContextWindow': 258400,
        'total': {'totalTokens': 500},
      },
      {
        'last': {'totalTokens': 500},
      },
      {
        'modelContextWindow': 0,
        'last': {'totalTokens': 500},
      },
      {
        'modelContextWindow': 258400,
        'last': {'totalTokens': -1},
      },
      {
        'modelContextWindow': 258400,
        'last': {'totalTokens': 1.5},
      },
      {
        'modelContextWindow': 258400,
        'last': {'inputTokens': 500},
      },
    ]) {
      expect(readContextWindowUsage(data), isNull, reason: '$data');
    }
    expect(
      ContextWindowUsage.tryParse({'usedTokens': 1, 'maxTokens': 0}),
      isNull,
    );
  });

  test('clamps the ring while preserving actual counts above the limit', () {
    const usage = ContextWindowUsage(usedTokens: 300000, maxTokens: 258400);
    expect(usage.fraction, 1);
    expect(usage.percent, 100);
    expect(usage.usedTokens, 300000);
  });

  test('compaction can reduce context and stale history cannot undo it', () {
    final older = ContextWindowUsage(
      usedTokens: 208000,
      maxTokens: 258400,
      updatedAt: DateTime.utc(2026, 9, 10, 12),
    );
    final compacted = ContextWindowUsage(
      usedTokens: 40000,
      maxTokens: 258400,
      updatedAt: DateTime.utc(2026, 9, 10, 12, 1),
    );
    expect(newerContextWindowUsage(older, compacted), compacted);
    expect(newerContextWindowUsage(compacted, older), compacted);
    expect(newerContextWindowUsage(compacted, null), compacted);
    expect(
      latestContextWindowUsage([
        SessionEvent(
          kind: 'token_usage',
          text: '',
          turnId: 't',
          contextWindowUsage: compacted,
        ),
        SessionEvent(
          kind: 'done',
          text: '',
          turnId: 't',
          contextWindowUsage: older,
        ),
      ]),
      compacted,
    );
  });

  test('late earlier-turn metadata does not replace the current context', () {
    const first = ContextWindowUsage(usedTokens: 208000, maxTokens: 258400);
    const second = ContextWindowUsage(usedTokens: 40000, maxTokens: 258400);
    final events = [
      const SessionEvent(
        kind: 'done',
        text: '',
        turnId: 'first',
        contextWindowUsage: first,
      ),
      const SessionEvent(
        kind: 'token_usage',
        text: '',
        turnId: 'second',
        contextWindowUsage: second,
      ),
    ];
    insertAnswerMetadata(
      events,
      const SessionEvent(
        kind: 'token_usage',
        text: '',
        turnId: 'first',
        contextWindowUsage: first,
      ),
    );
    expect(latestContextWindowUsage(events), second);
  });

  test('switching cached tasks restores only that task context', () async {
    final cache = SessionCache(backend: MemorySessionCacheBackend());
    addTearDown(cache.close);
    const scope = SessionCacheScope(
      key: 'context-test',
      pairingId: 'p',
      spaceId: 's',
      endpointId: 'e',
      targetDeviceId: 'd',
    );
    const first = ContextWindowUsage(usedTokens: 208000, maxTokens: 258400);
    const second = ContextWindowUsage(usedTokens: 40000, maxTokens: 128000);
    for (final entry in {'first': first, 'second': second}.entries) {
      await cache.saveTimeline(scope, entry.key, [
        SessionEvent(
          kind: 'done',
          text: '',
          turnId: 't',
          itemId: 'turn-end:t',
          contextWindowUsage: entry.value,
        ),
      ]);
    }
    expect(
      latestContextWindowUsage(await cache.loadTimeline(scope, 'second')),
      second,
    );
    expect(
      latestContextWindowUsage(await cache.loadTimeline(scope, 'first')),
      first,
    );
    expect(
      latestContextWindowUsage(await cache.loadTimeline(scope, 'new')),
      isNull,
    );
  });
}
