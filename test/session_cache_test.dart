import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:recodex/app/models/bridge_models.dart';
import 'package:recodex/app/services/session_cache.dart';
import 'package:recodex/app/services/session_cache_backend.dart';

void main() {
  group('SessionCache', () {
    test(
      'saves and restores the catalog without reading every timeline',
      () async {
        final backend = _RecordingCacheBackend();
        final cache = SessionCache(backend: backend);
        addTearDown(cache.close);
        final scope = _scope('catalog');
        final session = _session('thread-1');
        final workspace = const WorkspaceInfo(
          id: 'project-1',
          name: 'recodex',
          path: '/work/recodex',
        );

        await cache.saveCatalog(
          scope,
          sessions: [session],
          workspaces: [workspace],
          lastSequence: 18,
          syncedAt: DateTime.utc(2026, 9, 4, 12),
        );
        await cache.saveTimeline(scope, session.id, [
          const SessionEvent(kind: 'assistant', text: 'cached answer'),
        ]);
        final snapshot = await cache.load(scope);
        expect(snapshot.sessions.single.id, session.id);
        expect(snapshot.workspaces.single.path, workspace.path);
        expect(snapshot.lastSequence, 18);
        expect(snapshot.eventsByThread, isEmpty);
        expect(backend.readTimelineCalls, 0);

        final selected = await cache.load(scope, timelineThreadId: session.id);
        expect(
          selected.eventsByThread[session.id]!.single.text,
          'cached answer',
        );
        expect(backend.readTimelineCalls, 1);
      },
    );

    test('keeps timeline data isolated by cache scope', () async {
      final cache = SessionCache(backend: MemorySessionCacheBackend());
      addTearDown(cache.close);
      final first = _scope('first');
      final second = _scope('second');
      await cache.saveTimeline(first, 'same-thread-id', [
        const SessionEvent(kind: 'assistant', text: 'first space'),
      ]);
      await cache.saveTimeline(second, 'same-thread-id', [
        const SessionEvent(kind: 'assistant', text: 'second space'),
      ]);

      expect(
        (await cache.loadTimeline(first, 'same-thread-id')).single.text,
        'first space',
      );
      expect(
        (await cache.loadTimeline(second, 'same-thread-id')).single.text,
        'second space',
      );
    });

    test('incremental writes upsert only changed rows', () async {
      final backend = _RecordingCacheBackend();
      final cache = SessionCache(backend: backend);
      addTearDown(cache.close);
      final scope = _scope('incremental');
      final initial = const SessionEvent(
        kind: 'assistant',
        text: 'part one',
        itemId: 'item-1',
        turnId: 'turn-1',
      );
      await cache.saveTimeline(scope, 'thread-1', [initial]);
      expect(backend.replaceCalls, 1);

      await cache.saveTimelineIncremental(scope, 'thread-1', [initial]);
      expect(backend.upsertCalls, 0);

      final changed = initial.copyWith(text: 'part one and two');
      await cache.saveTimelineIncremental(scope, 'thread-1', [changed]);
      expect(backend.upsertCalls, 1);
      expect(backend.lastUpsertItemCount, 1);
      expect(
        (await cache.loadTimeline(scope, 'thread-1')).single.text,
        'part one and two',
      );
    });

    test('bounds timelines to 500 events', () async {
      final cache = SessionCache(backend: MemorySessionCacheBackend());
      addTearDown(cache.close);
      final events = List<SessionEvent>.generate(
        501,
        (index) => SessionEvent(
          kind: index == 0 ? 'user' : 'assistant',
          text: 'event-$index',
          itemId: 'item-$index',
          turnId: 'turn-1',
        ),
      );
      await cache.saveTimeline(_scope('bounded'), 'thread-1', events);
      final loaded = await cache.loadTimeline(_scope('bounded'), 'thread-1');
      expect(loaded, hasLength(500));
      expect(loaded.first.kind, 'user');
      expect(loaded.any((event) => event.text == 'event-500'), isTrue);
      expect(loaded.any((event) => event.text == 'event-1'), isFalse);
    });

    test('keeps the full latest window when no prompt is available', () async {
      final cache = SessionCache(backend: MemorySessionCacheBackend());
      addTearDown(cache.close);
      final events = List<SessionEvent>.generate(
        501,
        (index) => SessionEvent(kind: 'assistant', text: 'event-$index'),
      );

      await cache.saveTimeline(_scope('bounded-no-user'), 'thread-1', events);
      final loaded = await cache.loadTimeline(
        _scope('bounded-no-user'),
        'thread-1',
      );
      expect(loaded, hasLength(500));
      expect(loaded.first.text, 'event-1');
      expect(loaded.last.text, 'event-500');
    });

    test('does not shrink the window when the prompt is recent', () async {
      final cache = SessionCache(backend: MemorySessionCacheBackend());
      addTearDown(cache.close);
      final events = List<SessionEvent>.generate(
        501,
        (index) => SessionEvent(
          kind: index == 499 ? 'user' : 'assistant',
          text: 'event-$index',
        ),
      );

      await cache.saveTimeline(
        _scope('bounded-recent-user'),
        'thread-1',
        events,
      );
      final loaded = await cache.loadTimeline(
        _scope('bounded-recent-user'),
        'thread-1',
      );
      expect(loaded, hasLength(500));
      expect(loaded.first.text, 'event-1');
      expect(loaded.last.text, 'event-500');
    });

    test(
      'clips large inline attachments but keeps refreshable sources',
      () async {
        final cache = SessionCache(backend: MemorySessionCacheBackend());
        addTearDown(cache.close);
        final attachment = EventAttachment(
          type: 'image',
          mime: 'image/png',
          dataUrl: 'data:image/png;base64,${'a' * 70 * 1024}',
          thumbnailDataUrl: 'data:image/png;base64,small',
          resourceUrl: 'https://relay.invalid/resource/1',
        );
        await cache.saveTimeline(_scope('attachment'), 'thread-1', [
          SessionEvent(
            kind: 'assistant',
            text: 'image',
            attachments: [attachment],
          ),
        ]);

        final loaded = await cache.loadTimeline(
          _scope('attachment'),
          'thread-1',
        );
        final restored = loaded.single.attachments.single;
        expect(restored.dataUrl, isEmpty);
        expect(restored.thumbnailDataUrl, contains('small'));
        expect(restored.resourceUrl, contains('/resource/1'));
      },
    );

    test('corrupt cache rows fail open as an empty snapshot', () async {
      final backend = MemorySessionCacheBackend();
      final cache = SessionCache(backend: backend);
      addTearDown(cache.close);
      final scope = _scope('corrupt');
      await backend.writeCatalog(
        scope.key,
        const SessionCacheCatalogRow(
          sessionsJson: '{not-json',
          workspacesJson: '[]',
          lastSequence: 4,
          syncedAtMillis: null,
        ),
      );
      await backend.replaceTimeline(scope.key, 'thread-1', const [
        SessionCacheTimelineItem(
          key: 'broken',
          ordinal: 0,
          payload: '{not-json',
        ),
      ]);

      final snapshot = await cache.load(scope);
      expect(snapshot.sessions, isEmpty);
      expect(await cache.loadTimeline(scope, 'thread-1'), isEmpty);
    });

    test(
      'skips one malformed catalog item without losing valid rows',
      () async {
        final backend = MemorySessionCacheBackend();
        final cache = SessionCache(backend: backend);
        addTearDown(cache.close);
        final scope = _scope('partial-catalog');
        await backend.writeCatalog(
          scope.key,
          SessionCacheCatalogRow(
            sessionsJson: jsonEncode([
              _session('valid').toJson(),
              {
                'id': 42,
                'status': <String, Object>{'bad': true},
              },
            ]),
            workspacesJson: jsonEncode([
              const WorkspaceInfo(
                id: 'workspace-valid',
                name: 'recodex',
                path: '/work/recodex',
              ).toJson(),
              42,
            ]),
            lastSequence: 2,
            syncedAtMillis: null,
          ),
        );

        final snapshot = await cache.load(scope);
        expect(snapshot.sessions.single.id, 'valid');
        expect(snapshot.workspaces.single.id, 'workspace-valid');
      },
    );

    test('retries opening after a transient backend failure', () async {
      final backend = _RetryingCacheBackend();
      final cache = SessionCache(backend: backend);
      addTearDown(cache.close);

      await expectLater(cache.open(), throwsA(isA<StateError>()));
      await cache.open();
      expect(backend.openCalls, 2);
    });
  });
}

SessionCacheScope _scope(String suffix) {
  return SessionCacheScope(
    key: 'scope-$suffix',
    pairingId: 'pairing-$suffix',
    spaceId: 'space-$suffix',
    endpointId: 'app-$suffix',
    targetDeviceId: 'host-$suffix',
  );
}

SessionRecord _session(String id) {
  return SessionRecord(
    id: id,
    workspace: '/work/recodex',
    prompt: 'prompt',
    status: 'completed',
    createdAt: '2026-09-04T12:00:00Z',
    updatedAt: '2026-09-04T12:00:01Z',
  );
}

class _RecordingCacheBackend extends MemorySessionCacheBackend {
  int readTimelineCalls = 0;
  int replaceCalls = 0;
  int upsertCalls = 0;
  int lastUpsertItemCount = 0;

  @override
  Future<List<SessionCacheTimelineItem>> readTimeline(
    String scope,
    String threadId,
  ) async {
    readTimelineCalls += 1;
    return super.readTimeline(scope, threadId);
  }

  @override
  Future<void> replaceTimeline(
    String scope,
    String threadId,
    List<SessionCacheTimelineItem> items,
  ) async {
    replaceCalls += 1;
    return super.replaceTimeline(scope, threadId, items);
  }

  @override
  Future<void> upsertTimeline(
    String scope,
    String threadId,
    List<SessionCacheTimelineItem> items, {
    Set<String> removeKeys = const <String>{},
  }) async {
    upsertCalls += 1;
    lastUpsertItemCount = items.length;
    return super.upsertTimeline(scope, threadId, items, removeKeys: removeKeys);
  }
}

class _RetryingCacheBackend extends MemorySessionCacheBackend {
  var openCalls = 0;

  @override
  Future<void> open() async {
    openCalls += 1;
    if (openCalls == 1) throw StateError('transient');
    return super.open();
  }
}
