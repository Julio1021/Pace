import 'package:flutter/foundation.dart';

import '../data/database.dart';
import '../domain/coach.dart';
import '../domain/models.dart';
import '../domain/stats.dart';

/// Estado global: perfil e lista de corridas concluídas (mais recentes primeiro).
class AppState extends ChangeNotifier {
  PaceDatabase? _db;
  UserProfile profile = const UserProfile();
  List<Activity> activities = const [];
  bool ready = false;
  String? error;

  /// Animação de abertura com o Guará (uma vez por dia).
  bool introEnabled = true;

  /// Estilo das mensagens durante a corrida.
  CoachStyle coachStyle = CoachStyle.energetic;

  /// Voz das falas ('' = feminina automática).
  String voiceName = '';
  bool showIntroNow = false;

  PaceDatabase get db => _db!;

  Future<void> init({PaceDatabase? database}) async {
    try {
      _db = database ?? await PaceDatabase.open();
      profile = await db.getProfile();
      activities = await db.listActivities();
      introEnabled = (await db.getKv('intro_enabled')) != '0';
      coachStyle = CoachStyleX.parse(await db.getKv('coach_style'));
      voiceName = await db.getKv('tts_voice') ?? '';
      final last = await db.getKv('intro_last_day');
      final open = await db.listActivities(status: ActivityStatus.inProgress);
      final today = _dayKey(DateTime.now());
      showIntroNow = introEnabled && profile.isComplete && open.isEmpty && last != today;
    } catch (e) {
      error = 'Não foi possível abrir o banco de dados: $e';
    }
    ready = true;
    notifyListeners();
  }

  static String _dayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

  /// Marca a abertura de hoje como vista.
  Future<void> introShown() async {
    showIntroNow = false;
    notifyListeners();
    await db.setKv('intro_last_day', _dayKey(DateTime.now()));
  }

  Future<void> setVoiceName(String v) async {
    voiceName = v;
    notifyListeners();
    await db.setKv('tts_voice', v);
  }

  Future<void> setCoachStyle(CoachStyle s) async {
    coachStyle = s;
    notifyListeners();
    await db.setKv('coach_style', s.key);
  }

  Future<void> setIntroEnabled(bool v) async {
    introEnabled = v;
    notifyListeners();
    await db.setKv('intro_enabled', v ? '1' : '0');
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
