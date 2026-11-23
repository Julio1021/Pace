import 'models.dart';
import 'stats.dart';

/// Grupos de conquistas, para organizar a tela.
enum BadgeGroup { firsts, distance, volume, habit, speed }

extension BadgeGroupX on BadgeGroup {
  String get label => switch (this) {
        BadgeGroup.firsts => 'Primeiros passos',
        BadgeGroup.distance => 'Distâncias',
        BadgeGroup.volume => 'Quilometragem acumulada',
        BadgeGroup.habit => 'Constância e horários',
        BadgeGroup.speed => 'Velocidade',
      };
}

/// Uma conquista: nome, descrição, e se/quando foi desbloqueada.
class Achievement {
  final String id;
  final BadgeGroup group;
  final String title;
  final String description;

  /// Ícone (nome de Material Icon resolvido na interface) e cor de destaque.
  final String icon;
  final int color;

  /// Nível do metal: 0 bronze, 1 prata, 2 ouro, 3 platina.
  final int tier;

  /// Data em que foi desbloqueada (UTC) e a corrida responsável, se houver.
  final DateTime? unlockedAt;
  final int? activityId;

  /// Progresso de 0 a 1 enquanto bloqueada, e o texto do progresso.
  final double progress;
  final String? progressText;

  const Achievement({
    required this.id,
    required this.group,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    this.tier = 0,
    this.unlockedAt,
    this.activityId,
    this.progress = 0,
    this.progressText,
  });

  bool get unlocked => unlockedAt != null;
}

/// Calcula todas as conquistas percorrendo o histórico em ordem cronológica.
/// [efforts]: {idDaCorrida: {metros: segundos}} dos melhores esforços.
List<Achievement> computeAchievements(
  List<Activity> activities,
  Map<int, Map<int, int>> efforts, {
  double weeklyGoalKm = 0,
  DateTime? now,
}) {
  final asc = [...activities]..sort((a, b) => a.start.compareTo(b.start));
  final unlocked = <String, (DateTime, int?)>{};
  void hit(String id, Activity a) => unlocked.putIfAbsent(id, () => (a.start, a.id));

  var totalM = 0.0;
  var count = 0;
  final weekKm = <DateTime, double>{};
  final monthKm = <DateTime, double>{};
  final weeksWithRun = <DateTime>{};
  var goalWeeks = 0;
  final countedGoalWeeks = <DateTime>{};
  var maxStreak = 0;
  var earlyCount = 0;
  var nightCount = 0;

  for (final a in asc) {
    count++;
    totalM += a.distanceM;
    final l = a.start.toLocal();
    final w = Periods.weekStart(l);
    final m = Periods.monthStart(l);
    weekKm[w] = (weekKm[w] ?? 0) + a.distanceM / 1000;
    monthKm[m] = (monthKm[m] ?? 0) + a.distanceM / 1000;
    weeksWithRun.add(w);

    hit('first_run', a);
    if (count >= 10) hit('runs_10', a);
    if (count >= 50) hit('runs_50', a);
    if (count >= 100) hit('runs_100', a);
    if (count >= 250) hit('runs_250', a);

    if (a.distanceM >= 5000) hit('dist_5k', a);
    if (a.distanceM >= 10000) hit('dist_10k', a);
    if (a.distanceM >= 15000) hit('dist_15k', a);
    if (a.distanceM >= 21097) hit('dist_21k', a);
    if (a.distanceM >= 42195) hit('dist_42k', a);
    if (a.movingSec >= 3600) hit('hour_run', a);

    for (final (id, km) in [
      ('total_50', 50),
      ('total_100', 100),
      ('total_250', 250),
      ('total_500', 500),
      ('total_1000', 1000),
      ('total_2500', 2500),
    ]) {
      if (totalM / 1000 >= km) hit(id, a);
    }
    if ((monthKm[m] ?? 0) >= 100) hit('month_100', a);
    if ((weekKm[w] ?? 0) >= 30) hit('week_30', a);

    if (l.hour < 6) {
      earlyCount++;
      hit('early_bird', a);
      if (earlyCount >= 10) hit('early_bird_10', a);
    }
    if (l.hour >= 20) {
      nightCount++;
      hit('night_owl', a);
      if (nightCount >= 10) hit('night_owl_10', a);
    }
    if (a.elevGain >= 100) hit('climb_100', a);

    if (weeklyGoalKm > 0 && (weekKm[w] ?? 0) >= weeklyGoalKm && countedGoalWeeks.add(w)) {
      goalWeeks++;
      hit('goal_week_1', a);
      if (goalWeeks >= 10) hit('goal_week_10', a);
    }

    // Semanas seguidas com pelo menos uma corrida.
    var streak = 0;
    for (var d = w; weeksWithRun.contains(d); d = DateTime(d.year, d.month, d.day - 7)) {
      streak++;
    }
    if (streak > maxStreak) maxStreak = streak;
    if (streak >= 4) hit('streak_4', a);
    if (streak >= 8) hit('streak_8', a);
    if (streak >= 12) hit('streak_12', a);
    if (streak >= 26) hit('streak_26', a);

    final e = efforts[a.id] ?? const {};
    final p = a.paceSecPerKm;
    if ((e[5000] ?? 1 << 30) < 30 * 60) hit('sub30_5k', a);
    if ((e[5000] ?? 1 << 30) < 25 * 60) hit('sub25_5k', a);
    if ((e[10000] ?? 1 << 30) < 60 * 60) hit('sub60_10k', a);
    if ((e[10000] ?? 1 << 30) < 50 * 60) hit('sub50_10k', a);
    if (a.distanceM >= 5000 && p != null && p < 360) hit('pace_6', a);
    if (a.distanceM >= 5000 && p != null && p < 300) hit('pace_5', a);
  }

  double bestEffort(int m) {
    var b = double.infinity;
    for (final e in efforts.values) {
      final s = e[m];
      if (s != null && s < b) b = s.toDouble();
    }
    return b;
  }

  final longest = asc.fold<double>(0, (v, a) => a.distanceM > v ? a.distanceM : v);
  final maxMonth = monthKm.values.fold<double>(0, (v, x) => x > v ? x : v);
  final maxWeek = weekKm.values.fold<double>(0, (v, x) => x > v ? x : v);
  final maxClimb = asc.fold<double>(0, (v, a) => a.elevGain > v ? a.elevGain : v);

  String km(double v) => v.toStringAsFixed(v >= 100 ? 0 : 1).replaceAll('.', ',');
  (double, String) prog(double have, double need, String unit) =>
      ((have / need).clamp(0.0, 1.0), '${km(have)} de ${km(need)} $unit');
  (double, String) countProg(int have, int need, String what) => ((have / need).clamp(0.0, 1.0), '$have de $need $what');
  (double, String) timeProg(double best, int targetSec) => best.isFinite
      ? ((targetSec / best).clamp(0.0, 1.0), 'Seu melhor: ${_mmss(best)}')
      : (0.0, 'Ainda sem esse trecho completo');

  final defs = <(String, BadgeGroup, String, String, String, int, (double, String)?)>[
    ('first_run', BadgeGroup.firsts, 'Primeira passada', 'Completou a primeira corrida.', 'flag', 0xFF14B887, null),
    ('runs_10', BadgeGroup.firsts, '10 corridas', 'Completou 10 corridas.', 'repeat', 0xFF14B887, countProg(count, 10, 'corridas')),
    ('runs_50', BadgeGroup.firsts, '50 corridas', 'Completou 50 corridas.', 'repeat', 0xFF0EA5E9, countProg(count, 50, 'corridas')),
    ('runs_100', BadgeGroup.firsts, '100 corridas', 'Completou 100 corridas.', 'repeat', 0xFF6D4AE0, countProg(count, 100, 'corridas')),
    ('runs_250', BadgeGroup.firsts, '250 corridas', 'Completou 250 corridas.', 'repeat', 0xFFF59E0B, countProg(count, 250, 'corridas')),
    ('dist_5k', BadgeGroup.distance, 'Primeiros 5 km', 'Correu 5 km numa única corrida.', 'route', 0xFF14B887, prog(longest / 1000, 5, 'km')),
    ('dist_10k', BadgeGroup.distance, 'Dez mil', 'Correu 10 km numa única corrida.', 'route', 0xFF0EA5E9, prog(longest / 1000, 10, 'km')),
    ('dist_15k', BadgeGroup.distance, '15 km', 'Correu 15 km numa única corrida.', 'route', 0xFF6D4AE0, prog(longest / 1000, 15, 'km')),
    ('dist_21k', BadgeGroup.distance, 'Meia maratona', 'Correu 21,1 km numa única corrida.', 'military_tech', 0xFFF59E0B, prog(longest / 1000, 21.1, 'km')),
    ('dist_42k', BadgeGroup.distance, 'Maratona', 'Correu 42,2 km numa única corrida.', 'emoji_events', 0xFFE11D48, prog(longest / 1000, 42.2, 'km')),
    ('hour_run', BadgeGroup.distance, 'Uma hora de pé', 'Correu 1 hora sem parar o relógio.', 'timer', 0xFF0EA5E9, null),
    ('climb_100', BadgeGroup.distance, 'Subideiro', '100 m de subida numa corrida.', 'terrain', 0xFF8B5CF6, prog(maxClimb, 100, 'm')),
    ('total_50', BadgeGroup.volume, '50 km', '50 km acumulados.', 'straighten', 0xFF14B887, prog(totalM / 1000, 50, 'km')),
    ('total_100', BadgeGroup.volume, '100 km', '100 km acumulados.', 'straighten', 0xFF14B887, prog(totalM / 1000, 100, 'km')),
    ('total_250', BadgeGroup.volume, '250 km', '250 km acumulados.', 'straighten', 0xFF0EA5E9, prog(totalM / 1000, 250, 'km')),
    ('total_500', BadgeGroup.volume, '500 km', '500 km acumulados.', 'straighten', 0xFF6D4AE0, prog(totalM / 1000, 500, 'km')),
    ('total_1000', BadgeGroup.volume, '1.000 km', '1.000 km acumulados.', 'public', 0xFFF59E0B, prog(totalM / 1000, 1000, 'km')),
    ('total_2500', BadgeGroup.volume, '2.500 km', '2.500 km acumulados.', 'public', 0xFFE11D48, prog(totalM / 1000, 2500, 'km')),
    ('week_30', BadgeGroup.volume, 'Semana forte', '30 km numa mesma semana.', 'date_range', 0xFF0EA5E9, prog(maxWeek, 30, 'km')),
    ('month_100', BadgeGroup.volume, 'Mês de 100', '100 km num mesmo mês.', 'calendar_month', 0xFF6D4AE0, prog(maxMonth, 100, 'km')),
    ('streak_4', BadgeGroup.habit, '4 semanas seguidas', 'Correu em 4 semanas seguidas.', 'local_fire_department', 0xFFF97316, countProg(maxStreak, 4, 'semanas')),
    ('streak_8', BadgeGroup.habit, '8 semanas seguidas', 'Correu em 8 semanas seguidas.', 'local_fire_department', 0xFFF97316, countProg(maxStreak, 8, 'semanas')),
    ('streak_12', BadgeGroup.habit, '12 semanas seguidas', 'Um trimestre inteiro sem falhar uma semana.', 'local_fire_department', 0xFFE11D48, countProg(maxStreak, 12, 'semanas')),
    ('streak_26', BadgeGroup.habit, 'Meio ano firme', '26 semanas seguidas correndo.', 'whatshot', 0xFFE11D48, countProg(maxStreak, 26, 'semanas')),
    ('goal_week_1', BadgeGroup.habit, 'Meta batida', 'Cumpriu a meta semanal.', 'check_circle', 0xFF14B887, null),
    ('goal_week_10', BadgeGroup.habit, 'Meta é meta', 'Cumpriu a meta semanal 10 vezes.', 'verified', 0xFF6D4AE0, countProg(goalWeeks, 10, 'semanas')),
    ('early_bird', BadgeGroup.habit, 'Madrugador', 'Começou uma corrida antes das 6h.', 'wb_twilight', 0xFFF59E0B, null),
    ('early_bird_10', BadgeGroup.habit, 'Clube das 5', '10 corridas antes das 6h.', 'wb_twilight', 0xFFF97316, countProg(earlyCount, 10, 'corridas')),
    ('night_owl', BadgeGroup.habit, 'Coruja', 'Começou uma corrida depois das 20h.', 'nights_stay', 0xFF6366F1, null),
    ('night_owl_10', BadgeGroup.habit, 'Notívago', '10 corridas depois das 20h.', 'nights_stay', 0xFF4F46E5, countProg(nightCount, 10, 'corridas')),
    ('sub30_5k', BadgeGroup.speed, '5 km abaixo de 30 min', 'Fez 5 km em menos de 30 minutos.', 'bolt', 0xFF14B887, timeProg(bestEffort(5000), 1800)),
    ('sub25_5k', BadgeGroup.speed, '5 km abaixo de 25 min', 'Fez 5 km em menos de 25 minutos.', 'bolt', 0xFFF59E0B, timeProg(bestEffort(5000), 1500)),
    ('sub60_10k', BadgeGroup.speed, '10 km abaixo de 1 hora', 'Fez 10 km em menos de 60 minutos.', 'speed', 0xFF0EA5E9, timeProg(bestEffort(10000), 3600)),
    ('sub50_10k', BadgeGroup.speed, '10 km abaixo de 50 min', 'Fez 10 km em menos de 50 minutos.', 'speed', 0xFFE11D48, timeProg(bestEffort(10000), 3000)),
    ('pace_6', BadgeGroup.speed, 'Abaixo de 6:00', 'Pace médio abaixo de 6:00/km numa corrida de 5 km ou mais.', 'trending_up', 0xFF6D4AE0, null),
    ('pace_5', BadgeGroup.speed, 'Abaixo de 5:00', 'Pace médio abaixo de 5:00/km numa corrida de 5 km ou mais.', 'trending_up', 0xFFE11D48, null),
  ];

  return [
    for (final d in defs)
      Achievement(
        id: d.$1,
        group: d.$2,
        title: d.$3,
        description: d.$4,
        icon: d.$5,
        color: d.$6,
        tier: _tiers[d.$1] ?? 0,
        unlockedAt: unlocked[d.$1]?.$1,
        activityId: unlocked[d.$1]?.$2,
        progress: unlocked.containsKey(d.$1) ? 1 : (d.$7?.$1 ?? 0),
        progressText: unlocked.containsKey(d.$1) ? null : d.$7?.$2,
      ),
  ];
}

String _mmss(double s) {
  final t = s.round();
  final h = t ~/ 3600, m = (t % 3600) ~/ 60, sec = t % 60;
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}' : '$m:${sec.toString().padLeft(2, '0')}';
}

/// Metal de cada conquista: fáceis em bronze, médias em prata, difíceis em ouro, lendárias em platina.
const _tiers = <String, int>{
  'runs_10': 0, 'runs_50': 1, 'runs_100': 2, 'runs_250': 3,
  'dist_5k': 0, 'dist_10k': 1, 'dist_15k': 1, 'dist_21k': 2, 'dist_42k': 3,
  'hour_run': 1, 'climb_100': 1,
  'total_50': 0, 'total_100': 1, 'total_250': 1, 'total_500': 2, 'total_1000': 2, 'total_2500': 3,
  'week_30': 1, 'month_100': 2,
  'streak_4': 0, 'streak_8': 1, 'streak_12': 2, 'streak_26': 3,
  'goal_week_1': 0, 'goal_week_10': 2,
  'early_bird': 0, 'early_bird_10': 1, 'night_owl': 0, 'night_owl_10': 1,
  'sub30_5k': 1, 'sub25_5k': 2, 'sub60_10k': 1, 'sub50_10k': 2,
  'pace_6': 1, 'pace_5': 2,
};
