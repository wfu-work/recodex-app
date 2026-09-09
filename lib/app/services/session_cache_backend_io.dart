import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as mobile_sql;
import 'package:sqflite_common/sqlite_api.dart' as sql;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi_sql;

import 'session_cache_backend_api.dart';

/// SQLite backend for Android, iOS, macOS, Windows, and Linux. The class is
/// kept behind a conditional import so Web builds never load a native plugin.
class SqliteSessionCacheBackend implements SessionCacheBackend {
  static const _databaseName = 'recodex_session_cache.sqlite';
  static const _schemaVersion = 1;

  sql.Database? _database;
  Future<void>? _opening;

  @override
  Future<void> open() async {
    if (_database != null) return;
    final pending = _opening;
    if (pending != null) return pending;
    final operation = _openInternal();
    _opening = operation;
    try {
      await operation;
    } finally {
      if (identical(_opening, operation)) _opening = null;
    }
  }

  Future<void> _openInternal() async {
    final factory = _databaseFactory();
    if (!_usesFlutterSqlite) ffi_sql.sqfliteFfiInit();

    final supportDirectory = await getApplicationSupportDirectory();
    final cacheDirectory = Directory(
      path.join(supportDirectory.path, 'recodex'),
    );
    await cacheDirectory.create(recursive: true);
    final database = await factory.openDatabase(
      path.join(cacheDirectory.path, _databaseName),
      options: sql.OpenDatabaseOptions(
        version: _schemaVersion,
        onConfigure: (db) async {
          // WAL makes the short catalog/timeline writes independent from UI
          // reads. Some old SQLite builds reject the pragma; cache startup
          // should still succeed in that case.
          try {
            await db.execute('PRAGMA journal_mode = WAL');
          } catch (_) {}
        },
        onCreate: (db, _) => _createSchema(db),
        onUpgrade: (db, oldVersion, newVersion) =>
            _upgradeSchema(db, oldVersion, newVersion),
      ),
    );
    _database = database;
  }

  Future<void> _createSchema(sql.Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cache_catalog (
        scope TEXT PRIMARY KEY NOT NULL,
        sessions_json TEXT NOT NULL,
        workspaces_json TEXT NOT NULL,
        last_sequence INTEGER NOT NULL DEFAULT 0,
        synced_at INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cache_timeline (
        scope TEXT NOT NULL,
        thread_id TEXT NOT NULL,
        event_key TEXT NOT NULL,
        ordinal INTEGER NOT NULL,
        payload TEXT NOT NULL,
        PRIMARY KEY (scope, thread_id, event_key)
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS cache_timeline_order
      ON cache_timeline(scope, thread_id, ordinal)
    ''');
  }

  Future<void> _upgradeSchema(
    sql.Database db,
    int oldVersion,
    int newVersion,
  ) async {
    // Version 1 is the initial schema. Keep this callback explicit so future
    // migrations can be added without deleting a user's cached conversations.
    if (oldVersion < 1 && newVersion >= 1) {
      await _createSchema(db);
    }
  }

  sql.DatabaseFactory _databaseFactory() {
    if (_usesFlutterSqlite) return mobile_sql.databaseFactory;
    return ffi_sql.databaseFactoryFfi;
  }

  bool get _usesFlutterSqlite =>
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  @override
  Future<SessionCacheCatalogRow?> readCatalog(String scope) async {
    final db = await _readyDatabase();
    if (db == null) return null;
    final rows = await db.query(
      'cache_catalog',
      columns: const [
        'sessions_json',
        'workspaces_json',
        'last_sequence',
        'synced_at',
      ],
      where: 'scope = ?',
      whereArgs: [scope],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return SessionCacheCatalogRow(
      sessionsJson: row['sessions_json']?.toString() ?? '[]',
      workspacesJson: row['workspaces_json']?.toString() ?? '[]',
      lastSequence: _asInt(row['last_sequence']),
      syncedAtMillis: _asNullableInt(row['synced_at']),
    );
  }

  @override
  Future<List<SessionCacheTimelineItem>> readTimeline(
    String scope,
    String threadId,
  ) async {
    final db = await _readyDatabase();
    if (db == null) return const [];
    final rows = await db.query(
      'cache_timeline',
      columns: const ['event_key', 'ordinal', 'payload'],
      where: 'scope = ? AND thread_id = ?',
      whereArgs: [scope, threadId],
      orderBy: 'ordinal ASC, event_key ASC',
    );
    return rows
        .map(
          (row) => SessionCacheTimelineItem(
            key: row['event_key']?.toString() ?? '',
            ordinal: _asInt(row['ordinal']),
            payload: row['payload']?.toString() ?? '{}',
          ),
        )
        .where((item) => item.key.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<void> writeCatalog(String scope, SessionCacheCatalogRow row) async {
    final db = await _readyDatabase();
    if (db == null) return;
    await db.insert('cache_catalog', {
      'scope': scope,
      'sessions_json': row.sessionsJson,
      'workspaces_json': row.workspacesJson,
      'last_sequence': row.lastSequence,
      'synced_at': row.syncedAtMillis,
    }, conflictAlgorithm: sql.ConflictAlgorithm.replace);
  }

  @override
  Future<void> replaceTimeline(
    String scope,
    String threadId,
    List<SessionCacheTimelineItem> items,
  ) async {
    final db = await _readyDatabase();
    if (db == null) return;
    await db.transaction((txn) async {
      await txn.delete(
        'cache_timeline',
        where: 'scope = ? AND thread_id = ?',
        whereArgs: [scope, threadId],
      );
      for (final item in items) {
        await txn.insert('cache_timeline', {
          'scope': scope,
          'thread_id': threadId,
          'event_key': item.key,
          'ordinal': item.ordinal,
          'payload': item.payload,
        }, conflictAlgorithm: sql.ConflictAlgorithm.replace);
      }
    });
  }

  @override
  Future<void> upsertTimeline(
    String scope,
    String threadId,
    List<SessionCacheTimelineItem> items, {
    Set<String> removeKeys = const <String>{},
  }) async {
    final db = await _readyDatabase();
    if (db == null) return;
    await db.transaction((txn) async {
      for (final key in removeKeys) {
        await txn.delete(
          'cache_timeline',
          where: 'scope = ? AND thread_id = ? AND event_key = ?',
          whereArgs: [scope, threadId, key],
        );
      }
      for (final item in items) {
        await txn.insert('cache_timeline', {
          'scope': scope,
          'thread_id': threadId,
          'event_key': item.key,
          'ordinal': item.ordinal,
          'payload': item.payload,
        }, conflictAlgorithm: sql.ConflictAlgorithm.replace);
      }
    });
  }

  Future<sql.Database?> _readyDatabase() async {
    try {
      await open();
      return _database;
    } catch (_) {
      // SessionCache catches this as a best-effort failure and keeps its
      // in-memory state. Do not repeatedly throw from every event callback.
      return null;
    }
  }

  @override
  Future<void> close() async {
    final db = _database;
    _database = null;
    _opening = null;
    if (db != null) await db.close();
  }

  int _asInt(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  int? _asNullableInt(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }
}

SessionCacheBackend createSessionCacheBackend() => SqliteSessionCacheBackend();
