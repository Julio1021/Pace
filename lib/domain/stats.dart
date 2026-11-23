import 'models.dart';

/// Totais de um conjunto de corridas.
class PeriodStats {
  final int count;
  final double distanceM;
  final int movingSec;
  final double longestM;
  final int longestSec;
  final double? bestPace; // melhor pace médio entre corridas de pelo menos 1 km
  final double elevGain;
  final double calories;
  final int activeDays;

  const PeriodStats({
    this.count = 0,
    this.distanceM = 0,
    this.movingSec = 0,
    this.longestM = 0,
    this.longestSec = 0,
    this.bestPace,
    this.elevGain = 0,
    this.calories = 0,
    this.activeDays = 0,
  });

  double? get avgPace => distanceM >= 10 ? movingSec / (distanceM / 1000) : null;
  double? get avgSpeed => movingSec > 0 ? distanceM / movingSec : null;

  static PeriodStats of(Iterable<Activity> list) {
    var count = 0;
    var dist = 0.0;
    var mov = 0;
    var longest = 0.0;
    var longestSec = 0;
    double? best;
    var elev = 0.0;
    var cal = 0.0;
    final days = <String>{};
    for (final a in list) {
      count++;
      dist += a.distanceM;
      mov += a.movingSec;
      if (a.distanceM > longest) longest = a.distanceM;
      if (a.movingSec > longestSec) longestSec = a.movingSec;
      final p = a.paceSecPerKm;
      if (a.distanceM >= 1000 && p != null && (best == null || p < best)) best = p;
      elev += a.elevGain;
      cal += a.calories ?? 0;
      final l = a.start.toLocal();
      days.add('${l.year}-${l.month}-${l.day}');
    }
    return PeriodStats(
      count: count,
      distanceM: dist,
      movingSec: mov,
      longestM: longest,
      longestSec: longestSec,
      bestPace: best,
      elevGain: elev,
      calories: cal,
      activeDays: days.length,
    );
  }
}

/// Utilidades de datas (horário local) para agrupar corridas.
class Periods {
  static DateTime dayStart(DateTime local) => DateTime(local.year, local.month, local.day);

  /// Semana de segunda a domingo.
  static DateTime weekStart(DateTime local) {
    final d = dayStart(local);
    return d.subtract(Duration(days: d.weekday - DateTime.monday));
  }

  static DateTime monthStart(DateTime local) => DateTime(local.year, local.month);

  static Iterable<Activity> between(Iterable<Activity> list, DateTime fromLocal, DateTime toLocal) =>
      list.where((a) {
        final l = a.start.toLocal();
        return !l.isBefore(fromLocal) && l.isBefore(toLocal);
      });

  /// Variação relativa entre dois valores (null quando não há base).
  static double? change(double current, double previous) {
    if (previous <= 0) return null;
    return (current - previous) / previous;
  }
}

enum Bucket { day, week, month, year }

/// Quilometragem somada por dia, semana ou mês, de [fromLocal] até [toLocal] (exclusivo).
List<({DateTime start, double km})> kmBuckets(
  Iterable<Activity> list,
  DateTime fromLocal,
  DateTime toLocal,
  Bucket bucket,
) {
  DateTime norm(DateTime d) => switch (bucket) {
        Bucket.day => Periods.dayStart(d),
        Bucket.week => Periods.weekStart(d),
        Bucket.month => Periods.monthStart(d),
        Bucket.year => DateTime(d.year),
      };
  DateTime next(DateTime d) => switch (bucket) {
        Bucket.day => DateTime(d.year, d.month, d.day + 1),
        Bucket.week => DateTime(d.year, d.month, d.day + 7),
        Bucket.month => DateTime(d.year, d.month + 1),
        Bucket.year => DateTime(d.year + 1),
      };
  final sums = <DateTime, double>{};
  for (final a in Periods.between(list, fromLocal, toLocal)) {
    final k = norm(a.start.toLocal());
    sums[k] = (sums[k] ?? 0) + a.distanceM / 1000;
  }
  final out = <({DateTime start, double km})>[];
  for (var d = norm(fromLocal); d.isBefore(toLocal); d = next(d)) {
    out.add((start: d, km: sums[d] ?? 0));
  }
  return out;
}
