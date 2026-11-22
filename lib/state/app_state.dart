import 'package:flutter/foundation.dart';

import '../data/database.dart';
import '../domain/models.dart';
import '../domain/stats.dart';

/// Estado global: perfil e lista de corridas concluídas (mais recentes primeiro).
class AppState extends ChangeNotifier {
  PaceDatabase? _db;
  UserProfile profile = const UserProfile();
  List<Activity> activities = const [];
  bool ready = false;
  String? error;

  PaceDatabase get db => _db!;

  Future<void> init({PaceDatabase? database}) async {
    try {
      _db = database ?? await PaceDatabase.open();
      profile = await db.getProfile();
      activities = await db.listActivities();
    } catch (e) {
      error = 'Não foi possível abrir o banco de dados: $e';
    }
    ready = true;
    notifyListeners();
  }

  Future<void> reload() async {
    activities = await db.listActivities();
    notifyListeners();
  }

  Future<void> saveProfile(UserProfile p) async {
    await db.saveProfile(p);
    profile = p;
    notifyListeners();
  }

  Future<void> updateActivity(Activity a) async {
    await db.updateActivity(a);
    await reload();
  }

  Future<void> deleteActivity(int id) async {
    await db.deleteActivity(id);
    await reload();
  }

  // ---------- Totais prontos para as telas ----------

  PeriodStats get lifetime => PeriodStats.of(activities);

  DateTime? get firstRunDate => activities.isEmpty ? null : activities.last.start;

  PeriodStats weekStats(DateTime nowLocal, {int weeksAgo = 0}) {
    final start = Periods.weekStart(nowLocal).subtract(Duration(days: 7 * weeksAgo));
    final end = DateTime(start.year, start.month, start.day + 7);
    return PeriodStats.of(Periods.between(activities, start, end));
  }

  /// Mesmo trecho da semana anterior (de segunda até o mesmo dia/hora), para comparação justa.
  PeriodStats lastWeekSameSpan(DateTime nowLocal) {
    final thisStart = Periods.weekStart(nowLocal);
    final start = thisStart.subtract(const Duration(days: 7));
    final end = nowLocal.subtract(const Duration(days: 7));
    return PeriodStats.of(Periods.between(activities, start, end));
  }

  PeriodStats dayStats(DateTime nowLocal) {
    final start = Periods.dayStart(nowLocal);
    final end = DateTime(start.year, start.month, start.day + 1);
    return PeriodStats.of(Periods.between(activities, start, end));
  }
}
