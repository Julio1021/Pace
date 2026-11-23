import 'models.dart';
import 'stats.dart';

/// Distâncias de "melhor esforço" (trecho mais rápido dentro de qualquer corrida).
class EffortDistance {
  final int meters;
  final String label;
  final String short;
  const EffortDistance(this.meters, this.label, this.short);

  static const all = <EffortDistance>[
    EffortDistance(1000, '1 km', '1K'),
    EffortDistance(5000, '5 km', '5K'),
    EffortDistance(10000, '10 km', '10K'),
    EffortDistance(21097, 'Meia maratona', '21K'),
    EffortDistance(42195, 'Maratona', '42K'),
  ];
}

/// Calcula o trecho mais rápido (em tempo de movimento) para cada distância.
/// Usa distância e tempo acumulados dos pontos, com interpolação nas pontas.
/// Retorna {metros: segundos}.
Map<int, int> bestEfforts(List<TrackPoint> pts) {
  final out = <int, int>{};
  if (pts.length < 2) return out;
  final d = [for (final p in pts) p.dist];
  final t = [for (final p in pts) p.mov];
  final total = d.last;

  // Tempo (interpolado) em que a distância acumulada atinge x, buscando a partir de i.
  double timeAt(double x, int from) {
    var i = from;
    while (i < d.length - 1 && d[i + 1] < x) {
      i++;
    }
    if (i >= d.length - 1) return t.last;
    final span = d[i + 1] - d[i];
    if (span <= 0) return t[i + 1];
    return t[i] + (x - d[i]) / span * (t[i + 1] - t[i]);
  }

  for (final e in EffortDistance.all) {
    final target = e.meters.toDouble();
    if (total + 0.5 < target) continue;
    double? best;
    var j = 0;
    for (var i = 0; i < d.length; i++) {
      final endDist = d[i] + target;
      if (endDist > total + 0.5) break;
      while (j < d.length - 1 && d[j + 1] < endDist) {
        j++;
      }
      final te = timeAt(endDist, j);
      final dt = te - t[i];
      if (dt > 0 && (best == null || dt < best)) best = dt;
    }
    // Descarta trechos impossíveis (mais rápido que 9 m/s).
    if (best != null && best >= target / 9.0) out[e.meters] = best.round();
  }
  return out;
}

enum RecordKind { effort, longestRun, longestTime, biggestWeek, biggestMonth, mostClimb, fastestFiveKPlusRun }

class PersonalRecord {
  final RecordKind kind;
  final int? meters; // para esforços
  final String label;

  /// Segundos (esforços e duração), metros (distâncias, subida) ou s/km (pace).
  final double value;
  final int? activityId;
  final DateTime date; // UTC (início da corrida ou do período)

  const PersonalRecord({
    required this.kind,
    required this.label,
    required this.value,
    required this.date,
    this.meters,
    this.activityId,
  });

  String get key => kind == RecordKind.effort ? 'effort_$meters' : kind.name;
}

/// Todos os recordes pessoais a partir das corridas e dos esforços já calculados.
/// [efforts]: {idDaCorrida: {metros: segundos}}.
class Records {
  final List<PersonalRecord> list;
  const Records(this.list);

  PersonalRecord? byKey(String key) {
    for (final r in list) {
      if (r.key == key) return r;
    }
    return null;
  }

  static Records compute(List<Activity> activities, Map<int, Map<int, int>> efforts, {int? excludeId}) {
    final acts = [for (final a in activities) if (a.id != excludeId) a];
    final out = <PersonalRecord>[];
    for (final e in EffortDistance.all) {
      int? bestSec;
      Activity? holder;
      for (final a in acts) {
        final s = efforts[a.id]?[e.meters];
        if (s != null && (bestSec == null || s < bestSec)) {
          bestSec = s;
          holder = a;
        }
      }
      if (bestSec != null && holder != null) {
        out.add(PersonalRecord(
          kind: RecordKind.effort,
          meters: e.meters,
          label: e.label,
          value: bestSec.toDouble(),
          activityId: holder.id,
          date: holder.start,
        ));
      }
    }
    Activity? longest, longestT, climb, fastest;
    for (final a in acts) {
      if (longest == null || a.distanceM > longest.distanceM) longest = a;
      if (longestT == null || a.movingSec > longestT.movingSec) longestT = a;
      if (a.elevGain > 0 && (climb == null || a.elevGain > climb.elevGain)) climb = a;
      final p = a.paceSecPerKm;
      if (a.distanceM >= 5000 && p != null && (fastest == null || p < fastest.paceSecPerKm!)) fastest = a;
    }
    if (longest != null && longest.distanceM > 0) {
      out.add(PersonalRecord(
          kind: RecordKind.longestRun, label: 'Corrida mais longa', value: longest.distanceM, activityId: longest.id, date: longest.start));
    }
    if (longestT != null && longestT.movingSec > 0) {
      out.add(PersonalRecord(
          kind: RecordKind.longestTime,
          label: 'Mais tempo correndo',
          value: longestT.movingSec.toDouble(),
          activityId: longestT.id,
          date: longestT.start));
    }
    if (fastest != null) {
      out.add(PersonalRecord(
          kind: RecordKind.fastestFiveKPlusRun,
          label: 'Melhor pace médio (5 km ou mais)',
          value: fastest.paceSecPerKm!,
          activityId: fastest.id,
          date: fastest.start));
    }
    if (climb != null && climb.elevGain >= 1) {
      out.add(PersonalRecord(
          kind: RecordKind.mostClimb, label: 'Mais subida numa corrida', value: climb.elevGain, activityId: climb.id, date: climb.start));
    }
    // Maior semana e maior mês (por km).
    final weeks = <DateTime, double>{};
    final months = <DateTime, double>{};
    for (final a in acts) {
      final l = a.start.toLocal();
      final w = Periods.weekStart(l);
      final m = Periods.monthStart(l);
      weeks[w] = (weeks[w] ?? 0) + a.distanceM;
      months[m] = (months[m] ?? 0) + a.distanceM;
    }
    MapEntry<DateTime, double>? bw, bm;
    for (final e in weeks.entries) {
      if (bw == null || e.value > bw.value) bw = e;
    }
    for (final e in months.entries) {
      if (bm == null || e.value > bm.value) bm = e;
    }
    if (bw != null && bw.value > 0) {
      out.add(PersonalRecord(kind: RecordKind.biggestWeek, label: 'Maior semana', value: bw.value, date: bw.key.toUtc()));
    }
    if (bm != null && bm.value > 0) {
      out.add(PersonalRecord(kind: RecordKind.biggestMonth, label: 'Maior mês', value: bm.value, date: bm.key.toUtc()));
    }
    return Records(out);
  }

  /// Recordes que a corrida [id] bateu (comparando com o histórico sem ela).
  static List<({PersonalRecord now, PersonalRecord? before})> brokenBy(
    int id,
    List<Activity> activities,
    Map<int, Map<int, int>> efforts,
  ) {
    final withIt = compute(activities, efforts);
    final without = compute(activities, efforts, excludeId: id);
    final out = <({PersonalRecord now, PersonalRecord? before})>[];
    final me = activities.where((a) => a.id == id).firstOrNull;
    if (me == null) return out;
    for (final r in withIt.list) {
      final before = without.byKey(r.key);
      final mine = r.activityId == id ||
          ((r.kind == RecordKind.biggestWeek || r.kind == RecordKind.biggestMonth) && _samePeriod(r, me));
      if (!mine) continue;
      if (before == null || r.value != before.value) out.add((now: r, before: before));
    }
    return out;
  }

  static bool _samePeriod(PersonalRecord r, Activity a) {
    final l = a.start.toLocal();
    final start = r.kind == RecordKind.biggestWeek ? Periods.weekStart(l) : Periods.monthStart(l);
    return start.toUtc() == r.date;
  }
}
