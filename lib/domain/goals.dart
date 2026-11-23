import 'models.dart';
import 'stats.dart';

enum GoalPeriod { week, month, year }

extension GoalPeriodX on GoalPeriod {
  String get label => switch (this) {
        GoalPeriod.week => 'Semana',
        GoalPeriod.month => 'Mês',
        GoalPeriod.year => 'Ano',
      };
}

/// Progresso de uma meta de km num período, com previsão no ritmo atual.
class GoalStatus {
  final GoalPeriod period;
  final double targetKm;
  final double doneKm;
  final DateTime start; // local
  final DateTime end; // local, exclusivo
  final DateTime now;

  const GoalStatus({
    required this.period,
    required this.targetKm,
    required this.doneKm,
    required this.start,
    required this.end,
    required this.now,
  });

  double get progress => targetKm <= 0 ? 0 : (doneKm / targetKm).clamp(0.0, 9.99);
  bool get done => targetKm > 0 && doneKm >= targetKm;
  double get leftKm => (targetKm - doneKm).clamp(0.0, double.infinity);

  /// Fração do período já passada (0 a 1).
  double get elapsed {
    final total = end.difference(start).inMinutes;
    final gone = now.difference(start).inMinutes.clamp(0, total);
    return total <= 0 ? 1 : gone / total;
  }

  int get daysLeft {
    final today = DateTime(now.year, now.month, now.day);
    return end.difference(today).inDays.clamp(0, 400);
  }

  /// Onde você chega mantendo o ritmo atual (só faz sentido após alguns dias).
  double? get projectedKm {
    if (elapsed < 0.12 || doneKm <= 0) return null;
    return doneKm / elapsed;
  }

  /// km por semana necessários daqui até o fim para bater a meta.
  double? get neededPerWeek {
    if (done) return null;
    final weeks = daysLeft / 7;
    if (weeks <= 0) return null;
    return leftKm / (weeks < 1 ? 1 : weeks);
  }

  /// Adiantado (+) ou atrasado (-) em km em relação ao ritmo ideal.
  double get aheadKm => doneKm - targetKm * elapsed;

  static GoalStatus of(GoalPeriod p, double targetKm, List<Activity> acts, DateTime now) {
    final DateTime s, e;
    switch (p) {
      case GoalPeriod.week:
        s = Periods.weekStart(now);
        e = DateTime(s.year, s.month, s.day + 7);
      case GoalPeriod.month:
        s = Periods.monthStart(now);
        e = DateTime(s.year, s.month + 1);
      case GoalPeriod.year:
        s = DateTime(now.year);
        e = DateTime(now.year + 1);
    }
    final km = Periods.between(acts, s, e).fold<double>(0, (v, a) => v + a.distanceM / 1000);
    return GoalStatus(period: p, targetKm: targetKm, doneKm: km, start: s, end: e, now: now);
  }
}
