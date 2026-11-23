import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../domain/models.dart';

/// Banco local (SQLite). Todas as corridas ficam no celular.
class PaceDatabase {
  static const fileName = 'pace.db';
  static const version = 1;

  final Database db;
  PaceDatabase(this.db);

  static Future<PaceDatabase> open({DatabaseFactory? factory, String? path}) async {
    final f = factory ?? databaseFactory;
    final full = path ?? p.join(await f.getDatabasesPath(), fileName);
    final db = await f.openDatabase(
      full,
      options: OpenDatabaseOptions(
        version: version,
        onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, v) async => createSchema(db),
      ),
    );
    return PaceDatabase(db);
  }

  static Future<void> createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE activities (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        start INTEGER NOT NULL,
        end_time INTEGER,
        moving_sec INTEGER NOT NULL DEFAULT 0,
        elapsed_sec INTEGER NOT NULL DEFAULT 0,
        distance_m REAL NOT NULL DEFAULT 0,
        calories REAL,
        elev_gain REAL NOT NULL DEFAULT 0,
        elev_loss REAL NOT NULL DEFAULT 0,
        avg_hr INTEGER,
        max_hr INTEGER,
        avg_cad INTEGER,
        type TEXT NOT NULL DEFAULT 'Corrida livre',
        notes TEXT NOT NULL DEFAULT '',
        source TEXT NOT NULL,
        source_file TEXT,
        gps_partial INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL,
        best_km_sec INTEGER,
        lap_count INTEGER NOT NULL DEFAULT 0,
        preview TEXT NOT NULL DEFAULT ''
      )''');
    await db.execute('CREATE INDEX idx_act_start ON activities(start)');
    await db.execute('''
      CREATE TABLE points (
        activity_id INTEGER NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
        idx INTEGER NOT NULL,
        t INTEGER NOT NULL,
        lat REAL NOT NULL,
        lon REAL NOT NULL,
        alt REAL,
        acc REAL,
        speed REAL,
        hr INTEGER,
        cad INTEGER,
        dist REAL NOT NULL DEFAULT 0,
        mov REAL NOT NULL DEFAULT 0,
        paused INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (activity_id, idx)
      )''');
    await db.execute('''
      CREATE TABLE splits (
        activity_id INTEGER NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
        km INTEGER NOT NULL,
        dist_m REAL NOT NULL,
        sec REAL NOT NULL,
        PRIMARY KEY (activity_id, km)
      )''');
    await db.execute('''
      CREATE TABLE laps (
        activity_id INTEGER NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
        idx INTEGER NOT NULL,
        dist_m REAL NOT NULL,
        sec REAL NOT NULL,
        manual INTEGER NOT NULL DEFAULT 1,
        PRIMARY KEY (activity_id, idx)
      )''');
    await db.execute('CREATE TABLE kv (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
  }

  // ---------- Perfil e preferências ----------

  Future<String?> getKv(String key) async {
    final r = await db.query('kv', where: 'key = ?', whereArgs: [key]);
    return r.isEmpty ? null : r.first['value'] as String;
  }

  /// Todas as configurações guardadas (chave → valor).
  Future<Map<String, String>> allKv() async {
    final r = await db.query('kv');
    return {for (final m in r) '${m['key']}': '${m['value']}'};
  }

  Future<void> setKv(String key, String value) =>
      db.insert('kv', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<UserProfile> getProfile() async {
    final s = await getKv('profile');
    if (s == null) return const UserProfile();
    return UserProfile.fromJson(jsonDecode(s) as Map<String, Object?>);
  }

  Future<void> saveProfile(UserProfile p) => setKv('profile', jsonEncode(p.toJson()));

  // ---------- Atividades ----------

  Future<List<Activity>> listActivities({String status = ActivityStatus.done}) async {
    final r = await db.query('activities', where: 'status = ?', whereArgs: [status], orderBy: 'start DESC');
    return r.map(Activity.fromMap).toList();
  }

  Future<Activity?> getActivity(int id) async {
    final r = await db.query('activities', where: 'id = ?', whereArgs: [id]);
    return r.isEmpty ? null : Activity.fromMap(r.first);
  }

  Future<int> insertActivity(Activity a) => db.insert('activities', a.toMap()..remove('id'));

  Future<void> updateActivity(Activity a) =>
      db.update('activities', a.toMap()..remove('id'), where: 'id = ?', whereArgs: [a.id]);

  Future<void> deleteActivity(int id) async {
    await db.transaction((t) async {
      await t.delete('points', where: 'activity_id = ?', whereArgs: [id]);
      await t.delete('splits', where: 'activity_id = ?', whereArgs: [id]);
      await t.delete('laps', where: 'activity_id = ?', whereArgs: [id]);
      await t.delete('activities', where: 'id = ?', whereArgs: [id]);
    });
  }

  /// Grava uma atividade completa numa transação.
  Future<int> insertBundle(ActivityBundle b) async {
    return db.transaction((t) async {
      final id = await t.insert('activities', b.activity.toMap()..remove('id'));
      final batch = t.batch();
      for (var i = 0; i < b.points.length; i++) {
        batch.insert('points', b.points[i].toMap(id, i));
      }
      for (final s in b.splits) {
        batch.insert('splits', s.toMap(id));
      }
      for (final l in b.laps) {
        batch.insert('laps', l.toMap(id));
      }
      await batch.commit(noResult: true);
      return id;
    });
  }

  Future<void> appendPoints(int activityId, int firstIdx, List<TrackPoint> pts) async {
    if (pts.isEmpty) return;
    final batch = db.batch();
    for (var i = 0; i < pts.length; i++) {
      batch.insert('points', pts[i].toMap(activityId, firstIdx + i),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<void> replaceSplitsAndLaps(int activityId, List<Split> splits, List<Lap> laps) async {
    await db.transaction((t) async {
      await t.delete('splits', where: 'activity_id = ?', whereArgs: [activityId]);
      await t.delete('laps', where: 'activity_id = ?', whereArgs: [activityId]);
      final batch = t.batch();
      for (final s in splits) {
        batch.insert('splits', s.toMap(activityId));
      }
      for (final l in laps) {
        batch.insert('laps', l.toMap(activityId));
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<TrackPoint>> getPoints(int activityId) async {
    final r = await db.query('points', where: 'activity_id = ?', whereArgs: [activityId], orderBy: 'idx');
    return r.map(TrackPoint.fromMap).toList();
  }

  Future<List<Split>> getSplits(int activityId) async {
    final r = await db.query('splits', where: 'activity_id = ?', whereArgs: [activityId], orderBy: 'km');
    return r.map(Split.fromMap).toList();
  }

  Future<List<Lap>> getLaps(int activityId) async {
    final r = await db.query('laps', where: 'activity_id = ?', whereArgs: [activityId], orderBy: 'idx');
    return r.map(Lap.fromMap).toList();
  }

  Future<ActivityBundle?> getBundle(int id) async {
    final a = await getActivity(id);
    if (a == null) return null;
    return ActivityBundle(
      activity: a,
      points: await getPoints(id),
      splits: await getSplits(id),
      laps: await getLaps(id),
    );
  }

  /// Procura uma corrida equivalente: início até 2 min de diferença e distância até 3%.
  Future<Activity?> findDuplicate(DateTime startUtc, double distanceM) async {
    final ms = startUtc.millisecondsSinceEpoch;
    final r = await db.query(
      'activities',
      where: 'start BETWEEN ? AND ? AND status = ?',
      whereArgs: [ms - 120000, ms + 120000, ActivityStatus.done],
    );
    for (final m in r) {
      final a = Activity.fromMap(m);
      final base = distanceM > 0 ? distanceM : 1;
      if ((a.distanceM - distanceM).abs() / base <= 0.03) return a;
    }
    return null;
  }

  Future<void> close() => db.close();
}
