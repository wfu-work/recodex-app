import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:recodex/app/services/session_cache_backend_io.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test(
    'SQLite upgrades v1 without deleting history and persists scoped usage',
    () async {
      sqfliteFfiInit();
      final directory = await Directory.systemTemp.createTemp(
        'recodex-usage-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final databasePath = '${directory.path}/cache.sqlite';
      final old = await databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            await db.execute(
              'CREATE TABLE cache_timeline (scope TEXT, thread_id TEXT, event_key TEXT, ordinal INTEGER, payload TEXT)',
            );
            await db.insert('cache_timeline', {
              'scope': 'a',
              'thread_id': 't',
              'event_key': 'e',
              'ordinal': 0,
              'payload': 'preserved',
            });
          },
        ),
      );
      await old.close();
      var backend = SqliteSessionCacheBackend(
        factory: databaseFactoryFfi,
        databasePath: databasePath,
      );
      await backend.open();
      expect(
        (await backend.readTimeline('a', 't')).single.payload,
        'preserved',
      );
      await backend.upsertUsage('a', 't', {'turn': 'first'});
      await backend.upsertUsage('a', 't', {'turn': 'corrected'});
      await backend.upsertUsage('b', 't', {'turn': 'other host'});
      await backend.close();
      backend = SqliteSessionCacheBackend(
        factory: databaseFactoryFfi,
        databasePath: databasePath,
      );
      addTearDown(backend.close);
      expect(await backend.readUsage('a'), ['corrected']);
      expect(await backend.readUsage('b', threadId: 't'), ['other host']);
      expect(await backend.timelineThreadIds('a'), ['t']);
    },
  );
}
