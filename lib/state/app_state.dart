import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../data/database.dart';
import '../domain/achievements.dart';
import '../domain/coach.dart';
import '../domain/goals.dart';
import '../domain/models.dart';
import '../domain/plans.dart';
import '../domain/records.dart';
import '../domain/reminders.dart';
import '../domain/stats.dart';
import '../services/run_notification.dart';
import '../services/weather.dart';
import '../services/pcloud.dart';
import '../data/exporters.dart';

/// Treino do plano escolhido para a próxima corrida (preenche a tela Correr).
class RunPreset {
  final int sessionIndex;
  final String type;
  final bool byTime;
  final double value;
  final String label;
  const RunPreset({required this.sessionIndex, required this.type, required this.byTime, required this.value, required this.label});
}

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

  /// Avisos de voz a cada N km (1, 2, 3 ou 5).
  int voiceEveryKm = 1;
  bool showIntroNow = false;

  /// Melhores esforços por corrida: {id: {metros: segundos}}.
  Map<int, Map<int, int>> efforts = {};
  bool effortsBusy = false;

  /// Plano de treino em andamento.
  ActivePlan? plan;

  /// Treino do plano a carregar na tela Correr.
  RunPreset? pendingPreset;

  /// Lembretes agendados.
  ReminderSettings reminders = const ReminderSettings();

  // ---------- Backup no pCloud ----------

  PCloudService? pcloud;
  String? pcloudEmail;
  DateTime? lastCloudBackup;
  int _lastCloudCount = -1;
  bool cloudBusy = false;
  String? cloudError;

  bool get pcloudConnected => pcloud != null;

  Future<void> _loadCloud() async {
    try {
      final raw = await db.getKv('pcloud');
      if (raw == null || raw.isEmpty) return;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      pcloud = PCloudService('${j['token']}', '${j['host']}');
      pcloudEmail = j['email'] as String?;
      final t = (j['last'] as num?)?.toInt();
      lastCloudBackup = t == null ? null : DateTime.fromMillisecondsSinceEpoch(t);
      _lastCloudCount = (j['count'] as num?)?.toInt() ?? -1;
    } catch (_) {}
  }

  Future<void> _saveCloud() async {
    final c = pcloud;
    await db.setKv(
      'pcloud',
      c == null
          ? ''
          : jsonEncode({
              'token': c.token,
              'host': c.host,
              'email': pcloudEmail,
              'last': lastCloudBackup?.millisecondsSinceEpoch,
              'count': _lastCloudCount,
            }),
    );
  }

  /// Abre o login no navegador e espera a volta para o app.
  Future<void> connectPCloud() async {
    cloudError = null;
    cloudBusy = true;
    notifyListeners();
    try {
      await PCloudService.startLogin();
      final c = await PCloudService.waitForLogin();
      pcloud = c;
      try {
        pcloudEmail = await c.email();
      } catch (_) {}
      await _saveCloud();
      cloudBusy = false;
      notifyListeners();
      await backupToCloud();
    } catch (e) {
      cloudError = '$e';
    } finally {
      cloudBusy = false;
      notifyListeners();
    }
  }

  Future<void> disconnectPCloud() async {
    pcloud = null;
    pcloudEmail = null;
    lastCloudBackup = null;
    _lastCloudCount = -1;
    await _saveCloud();
    notifyListeners();
  }

  /// Envia um backup agora (e mantém só os 10 mais recentes).
  Future<bool> backupToCloud() async {
    final c = pcloud;
    if (c == null || cloudBusy) return false;
    cloudBusy = true;
    cloudError = null;
    notifyListeners();
    try {
      final bytes = Uint8List.fromList(await BackupCodec.build(db));
      final n = DateTime.now();
      String two(int v) => v.toString().padLeft(2, '0');
      await c.upload('pace_backup_${n.year}-${two(n.month)}-${two(n.day)}_${two(n.hour)}${two(n.minute)}.zip', bytes);
      try {
        await c.prune();
      } catch (_) {}
      lastCloudBackup = n;
      _lastCloudCount = activities.length;
      await _saveCloud();
      return true;
    } catch (e) {
      cloudError = '$e';
      if (e is PCloudException && e.message.contains('expirou')) await disconnectPCloud();
      return false;
    } finally {
      cloudBusy = false;
      notifyListeners();
    }
  }

  /// Automático: depois de uma corrida nova ou se passou uma semana.
  Future<void> _autoCloudBackup() async {
    if (pcloud == null) return;
    final last = lastCloudBackup;
    final changed = activities.length != _lastCloudCount;
    final old = last == null || DateTime.now().difference(last).inDays >= 7;
    if (changed || old) await backupToCloud();
  }

  Future<({int restored, int skipped})> restoreFromCloud(int fileId) async {
    final c = pcloud!;
    cloudBusy = true;
    notifyListeners();
    try {
      final bytes = await c.download(fileId);
      final r = await BackupCodec.restore(db, bytes);
      profile = await db.getProfile();
      await reload();
      return r;
    } finally {
      cloudBusy = false;
      notifyListeners();
    }
  }

  /// Tempo agora (para o céu da tela Correr).
  WeatherNow? weather;
  bool _weatherBusy = false;

  /// Atualiza a previsão se tiver mais de 30 min (sem internet, mantém a anterior).
  Future<void> refreshWeather(double lat, double lon) async {
    if (!autoBackground || _weatherBusy) return;
    final w = weather;
    if (w != null && DateTime.now().difference(w.fetchedAt).inMinutes < 30) return;
    _weatherBusy = true;
    try {
      final n = await WeatherService.fetch(lat, lon);
      if (n != null) {
        weather = n;
        notifyListeners();
        await db.setKv('weather', jsonEncode(n.toJson()));
      }
    } finally {
      _weatherBusy = false;
    }
  }

  PaceDatabase get db => _db!;

  /// Em testes o trabalho de fundo é chamado à mão (ver [afterChange]).
  bool autoBackground = true;

  Future<void> init({PaceDatabase? database}) async {
    try {
      _db = database ?? await PaceDatabase.open();
      profile = await db.getProfile();
      activities = await db.listActivities();
      introEnabled = (await db.getKv('intro_enabled')) != '0';
      coachStyle = CoachStyleX.parse(await db.getKv('coach_style'));
      voiceEveryKm = int.tryParse(await db.getKv('voice_every_km') ?? '') ?? 1;
      await _loadExtras();
      await _loadCloud();
      final last = await db.getKv('intro_last_day');
      final open = await db.listActivities(status: ActivityStatus.inProgress);
      final today = _dayKey(DateTime.now());
      showIntroNow = introEnabled && profile.isComplete && open.isEmpty && last != today;
    } catch (e) {
      error = 'Não foi possível abrir o banco de dados: $e';
    }
    ready = true;
    notifyListeners();
    if (error == null && autoBackground) unawaited(afterChange());
  }

  Future<void> _loadExtras() async {
    try {
      final raw = await db.getKv('efforts_v1');
      if (raw != null) {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        efforts = {
          for (final e in m.entries)
            int.parse(e.key): {for (final x in (e.value as Map<String, dynamic>).entries) int.parse(x.key): (x.value as num).toInt()},
        };
      }
    } catch (_) {
      efforts = {};
    }
    try {
      final p = await db.getKv('plan_active');
      plan = (p == null || p.isEmpty) ? null : ActivePlan.fromJson(jsonDecode(p) as Map<String, dynamic>);
    } catch (_) {
      plan = null;
    }
    try {
      final wr = await db.getKv('weather');
      if (wr != null) {
        final w = WeatherNow.fromJson(jsonDecode(wr) as Map<String, dynamic>);
        // Previsão guardada só vale por 3 horas.
        if (w != null && DateTime.now().difference(w.fetchedAt).inHours < 3) weather = w;
      }
    } catch (_) {}
    try {
      final r = await db.getKv('reminders');
      reminders = r == null ? ReminderSettings.suggested(activities, DateTime.now()) : ReminderSettings.fromJson(jsonDecode(r) as Map<String, dynamic>);
    } catch (_) {}
  }

  /// Depois de abrir o app ou mudar o histórico: esforços novos, plano e lembretes.
  Future<void> afterChange() async {
    await ensureEfforts();
    final p = plan;
    if (p != null) {
      final marked = p.autoMark(activities);
      if (!identical(marked, p)) await _savePlan(marked);
    }
    await rescheduleReminders();
    await _autoCloudBackup();
  }

  /// Calcula (uma vez) os melhores esforços das corridas que ainda não têm.
  Future<void> ensureEfforts() async {
    if (effortsBusy) return;
    final missing = [for (final a in activities) if (a.id != null && !efforts.containsKey(a.id)) a.id!];
    if (missing.isEmpty) return;
    effortsBusy = true;
    notifyListeners();
    try {
      var n = 0;
      for (final id in missing) {
        final pts = await db.getPoints(id);
        efforts = {...efforts, id: bestEfforts(pts)};
        if (++n % 25 == 0) {
          await _saveEfforts();
          notifyListeners();
        }
      }
      await _saveEfforts();
    } catch (_) {
    } finally {
      effortsBusy = false;
      _cache.clear();
      notifyListeners();
    }
  }

  Future<void> _saveEfforts() => db.setKv(
        'efforts_v1',
        jsonEncode({
          for (final e in efforts.entries) '${e.key}': {for (final x in e.value.entries) '${x.key}': x.value},
        }),
      );

  // ---------- Recordes, conquistas e metas (com cache) ----------

  final Map<String, Object> _cache = {};

  T _cached<T extends Object>(String key, T Function() build) {
    final k = '$key:${activities.length}:${activities.isEmpty ? 0 : activities.first.id}:${efforts.length}:${profile.weeklyGoalKm}';
    return (_cache[k] ??= build()) as T;
  }

  Records get records => _cached('records', () => Records.compute(activities, efforts));

  List<Achievement> get badges =>
      _cached('badges', () => computeAchievements(activities, efforts, weeklyGoalKm: profile.weeklyGoalKm));

  GoalStatus goal(GoalPeriod p, DateTime now) => GoalStatus.of(
        p,
        switch (p) {
          GoalPeriod.week => profile.weeklyGoalKm,
          GoalPeriod.month => profile.monthlyGoalKm,
          GoalPeriod.year => profile.yearlyGoalKm,
        },
        activities,
        now,
      );

  // ---------- Plano de treino ----------

  Future<void> _savePlan(ActivePlan? p) async {
    plan = p;
    notifyListeners();
    if (p == null) {
      await db.setKv('plan_active', '');
    } else {
      await db.setKv('plan_active', jsonEncode(p.toJson()));
    }
  }

  Future<void> startPlan(String id, DateTime startDay) async {
    await _savePlan(ActivePlan(planId: id, start: DateTime(startDay.year, startDay.month, startDay.day)));
    await rescheduleReminders();
  }

  Future<void> stopPlan() async {
    pendingPreset = null;
    await _savePlan(null);
    await rescheduleReminders();
  }

  Future<void> toggleSession(int index) async {
    final p = plan;
    if (p == null) return;
    final d = Map<int, int>.from(p.done);
    if (d.containsKey(index)) {
      d.remove(index);
    } else {
      d[index] = 0;
    }
    await _savePlan(p.copyWith(done: d));
    await rescheduleReminders();
  }

  void usePlanSession(int index) {
    final s = plan?.plan?.sessions[index];
    if (s == null) return;
    pendingPreset = RunPreset(
      sessionIndex: index,
      type: s.type,
      byTime: s.byTime,
      value: s.value,
      label: 'Semana ${s.week} · Treino ${s.n}',
    );
    notifyListeners();
  }

  void clearPreset() {
    pendingPreset = null;
  }

  // ---------- Lembretes ----------

  Future<void> setReminders(ReminderSettings r) async {
    reminders = r;
    notifyListeners();
    await db.setKv('reminders', jsonEncode(r.toJson()));
    await rescheduleReminders();
  }

  Future<void> rescheduleReminders() async {
    final notes = planReminders(
      activities: activities,
      s: reminders,
      weeklyGoalKm: profile.weeklyGoalKm,
      now: DateTime.now(),
      plan: plan,
    );
    await RunNotification.schedule([for (final n in notes) n.toJson()]);
  }

  static String _dayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

  /// Marca a abertura de hoje como vista.
  Future<void> introShown() async {
    showIntroNow = false;
    notifyListeners();
    await db.setKv('intro_last_day', _dayKey(DateTime.now()));
  }

  Future<void> setVoiceEveryKm(int v) async {
    voiceEveryKm = v;
    notifyListeners();
    await db.setKv('voice_every_km', '$v');
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
    _cache.clear();
    notifyListeners();
    if (autoBackground) unawaited(afterChange());
  }

  Future<void> saveProfile(UserProfile p) async {
    await db.saveProfile(p);
    profile = p;
    _cache.clear();
    notifyListeners();
    if (autoBackground) unawaited(rescheduleReminders());
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
