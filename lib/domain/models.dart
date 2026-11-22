/// Modelos do PACE. Todos os horários são guardados em UTC.
library;

enum ActivitySource { recorded, tcx, gpx }

extension ActivitySourceX on ActivitySource {
  String get key => switch (this) {
        ActivitySource.recorded => 'gravada',
        ActivitySource.tcx => 'importada_tcx',
        ActivitySource.gpx => 'importada_gpx',
      };

  String get label => switch (this) {
        ActivitySource.recorded => 'Gravada no PACE',
        ActivitySource.tcx => 'Importada (TCX)',
        ActivitySource.gpx => 'Importada (GPX)',
      };

  static ActivitySource parse(String? s) => switch (s) {
        'importada_tcx' => ActivitySource.tcx,
        'importada_gpx' => ActivitySource.gpx,
        _ => ActivitySource.recorded,
      };
}

class ActivityStatus {
  static const inProgress = 'em_andamento';
  static const done = 'concluida';
}

/// Tipos de treino disponíveis nesta etapa.
const trainingTypes = <String>[
  'Corrida livre',
  'Corrida leve',
  'Corrida contínua',
  'Intervalado',
  'Treino de ritmo',
  'Rodagem longa',
  'Recuperação',
  'Prova',
];

class Activity {
  final int? id;
  final DateTime start; // UTC
  final DateTime? end; // UTC
  final int movingSec;
  final int elapsedSec;
  final double distanceM;
  final double? calories;
  final double elevGain;
  final double elevLoss;
  final int? avgHr;
  final int? maxHr;
  final int? avgCad;
  final String type;
  final String notes;
  final ActivitySource source;
  final String? sourceFile;
  final bool gpsPartial;
  final String status;
  final int? bestKmSec;
  final int lapCount;

  /// Trajeto simplificado ("lat,lon;lat,lon") para miniaturas sem carregar os pontos.
  final String preview;

  const Activity({
    this.id,
    required this.start,
    this.end,
    this.movingSec = 0,
    this.elapsedSec = 0,
    this.distanceM = 0,
    this.calories,
    this.elevGain = 0,
    this.elevLoss = 0,
    this.avgHr,
    this.maxHr,
    this.avgCad,
    this.type = 'Corrida livre',
    this.notes = '',
    this.source = ActivitySource.recorded,
    this.sourceFile,
    this.gpsPartial = false,
    this.status = ActivityStatus.done,
    this.bestKmSec,
    this.lapCount = 0,
    this.preview = '',
  });

  double get km => distanceM / 1000;

  /// Pace médio em s/km (tempo em movimento ÷ distância).
  double? get paceSecPerKm => distanceM >= 10 ? movingSec / (distanceM / 1000) : null;

  /// Velocidade média em m/s.
  double? get avgSpeed => movingSec > 0 ? distanceM / movingSec : null;

  bool get hasRoute => preview.isNotEmpty;

  List<List<double>> get previewPoints {
    if (preview.isEmpty) return const [];
    final out = <List<double>>[];
    for (final p in preview.split(';')) {
      final parts = p.split(',');
      if (parts.length != 2) continue;
      final la = double.tryParse(parts[0]);
      final lo = double.tryParse(parts[1]);
      if (la != null && lo != null) out.add([la, lo]);
    }
    return out;
  }

  Activity copyWith({
    int? id,
    DateTime? start,
    DateTime? end,
    int? movingSec,
    int? elapsedSec,
    double? distanceM,
    double? calories,
    double? elevGain,
    double? elevLoss,
    int? avgHr,
    int? maxHr,
    int? avgCad,
    String? type,
    String? notes,
    ActivitySource? source,
    String? sourceFile,
    bool? gpsPartial,
    String? status,
    int? bestKmSec,
    int? lapCount,
    String? preview,
  }) =>
      Activity(
        id: id ?? this.id,
        start: start ?? this.start,
        end: end ?? this.end,
        movingSec: movingSec ?? this.movingSec,
        elapsedSec: elapsedSec ?? this.elapsedSec,
        distanceM: distanceM ?? this.distanceM,
        calories: calories ?? this.calories,
        elevGain: elevGain ?? this.elevGain,
        elevLoss: elevLoss ?? this.elevLoss,
        avgHr: avgHr ?? this.avgHr,
        maxHr: maxHr ?? this.maxHr,
        avgCad: avgCad ?? this.avgCad,
        type: type ?? this.type,
        notes: notes ?? this.notes,
        source: source ?? this.source,
        sourceFile: sourceFile ?? this.sourceFile,
        gpsPartial: gpsPartial ?? this.gpsPartial,
        status: status ?? this.status,
        bestKmSec: bestKmSec ?? this.bestKmSec,
        lapCount: lapCount ?? this.lapCount,
        preview: preview ?? this.preview,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'start': start.toUtc().millisecondsSinceEpoch,
        'end_time': end?.toUtc().millisecondsSinceEpoch,
        'moving_sec': movingSec,
        'elapsed_sec': elapsedSec,
        'distance_m': distanceM,
        'calories': calories,
        'elev_gain': elevGain,
        'elev_loss': elevLoss,
        'avg_hr': avgHr,
        'max_hr': maxHr,
        'avg_cad': avgCad,
        'type': type,
        'notes': notes,
        'source': source.key,
        'source_file': sourceFile,
        'gps_partial': gpsPartial ? 1 : 0,
        'status': status,
        'best_km_sec': bestKmSec,
        'lap_count': lapCount,
        'preview': preview,
      };

  static Activity fromMap(Map<String, Object?> m) => Activity(
        id: m['id'] as int?,
        start: DateTime.fromMillisecondsSinceEpoch(m['start'] as int, isUtc: true),
        end: m['end_time'] == null ? null : DateTime.fromMillisecondsSinceEpoch(m['end_time'] as int, isUtc: true),
        movingSec: (m['moving_sec'] as int?) ?? 0,
        elapsedSec: (m['elapsed_sec'] as int?) ?? 0,
        distanceM: ((m['distance_m'] as num?) ?? 0).toDouble(),
        calories: (m['calories'] as num?)?.toDouble(),
        elevGain: ((m['elev_gain'] as num?) ?? 0).toDouble(),
        elevLoss: ((m['elev_loss'] as num?) ?? 0).toDouble(),
        avgHr: m['avg_hr'] as int?,
        maxHr: m['max_hr'] as int?,
        avgCad: m['avg_cad'] as int?,
        type: (m['type'] as String?) ?? 'Corrida livre',
        notes: (m['notes'] as String?) ?? '',
        source: ActivitySourceX.parse(m['source'] as String?),
        sourceFile: m['source_file'] as String?,
        gpsPartial: (m['gps_partial'] as int? ?? 0) == 1,
        status: (m['status'] as String?) ?? ActivityStatus.done,
        bestKmSec: m['best_km_sec'] as int?,
        lapCount: (m['lap_count'] as int?) ?? 0,
        preview: (m['preview'] as String?) ?? '',
      );
}

class TrackPoint {
  final DateTime time; // UTC
  final double lat;
  final double lon;
  final double? alt;
  final double? accuracy;
  final double? speed;
  final int? hr;
  final int? cad;

  /// Distância acumulada (m) e tempo em movimento acumulado (s) até este ponto.
  final double dist;
  final double mov;

  /// Ponto registrado durante pausa (não soma distância).
  final bool paused;

  const TrackPoint({
    required this.time,
    required this.lat,
    required this.lon,
    this.alt,
    this.accuracy,
    this.speed,
    this.hr,
    this.cad,
    this.dist = 0,
    this.mov = 0,
    this.paused = false,
  });

  TrackPoint withProgress(double dist, double mov) => TrackPoint(
        time: time,
        lat: lat,
        lon: lon,
        alt: alt,
        accuracy: accuracy,
        speed: speed,
        hr: hr,
        cad: cad,
        dist: dist,
        mov: mov,
        paused: paused,
      );

  Map<String, Object?> toMap(int activityId, int idx) => {
        'activity_id': activityId,
        'idx': idx,
        't': time.toUtc().millisecondsSinceEpoch,
        'lat': lat,
        'lon': lon,
        'alt': alt,
        'acc': accuracy,
        'speed': speed,
        'hr': hr,
        'cad': cad,
        'dist': dist,
        'mov': mov,
        'paused': paused ? 1 : 0,
      };

  static TrackPoint fromMap(Map<String, Object?> m) => TrackPoint(
        time: DateTime.fromMillisecondsSinceEpoch(m['t'] as int, isUtc: true),
        lat: (m['lat'] as num).toDouble(),
        lon: (m['lon'] as num).toDouble(),
        alt: (m['alt'] as num?)?.toDouble(),
        accuracy: (m['acc'] as num?)?.toDouble(),
        speed: (m['speed'] as num?)?.toDouble(),
        hr: m['hr'] as int?,
        cad: m['cad'] as int?,
        dist: ((m['dist'] as num?) ?? 0).toDouble(),
        mov: ((m['mov'] as num?) ?? 0).toDouble(),
        paused: (m['paused'] as int? ?? 0) == 1,
      );
}

/// Parcial de 1 km (o último pode ser menor).
class Split {
  final int km;
  final double distM;
  final double sec;

  const Split({required this.km, required this.distM, required this.sec});

  double get paceSecPerKm => distM > 0 ? sec / (distM / 1000) : 0;

  Map<String, Object?> toMap(int activityId) => {
        'activity_id': activityId,
        'km': km,
        'dist_m': distM,
        'sec': sec,
      };

  static Split fromMap(Map<String, Object?> m) => Split(
        km: m['km'] as int,
        distM: (m['dist_m'] as num).toDouble(),
        sec: (m['sec'] as num).toDouble(),
      );
}

/// Volta (manual ou automática).
class Lap {
  final int index;
  final double distM;
  final double sec;
  final bool manual;

  const Lap({required this.index, required this.distM, required this.sec, this.manual = true});

  double get paceSecPerKm => distM > 0 ? sec / (distM / 1000) : 0;

  Map<String, Object?> toMap(int activityId) => {
        'activity_id': activityId,
        'idx': index,
        'dist_m': distM,
        'sec': sec,
        'manual': manual ? 1 : 0,
      };

  static Lap fromMap(Map<String, Object?> m) => Lap(
        index: m['idx'] as int,
        distM: (m['dist_m'] as num).toDouble(),
        sec: (m['sec'] as num).toDouble(),
        manual: (m['manual'] as int? ?? 1) == 1,
      );
}

class UserProfile {
  final String name;
  final DateTime? birthDate;
  final double? heightCm;
  final double? weightKg;
  final String? sex;
  final String level;
  final double weeklyGoalKm;

  const UserProfile({
    this.name = '',
    this.birthDate,
    this.heightCm,
    this.weightKg,
    this.sex,
    this.level = 'Iniciante',
    this.weeklyGoalKm = 15,
  });

  bool get isComplete => name.trim().isNotEmpty;

  /// Peso usado nos cálculos de calorias (70 kg quando não informado).
  double get weightForCalc => weightKg ?? 70;

  int? get age {
    final b = birthDate;
    if (b == null) return null;
    final now = DateTime.now();
    var a = now.year - b.year;
    if (now.month < b.month || (now.month == b.month && now.day < b.day)) a--;
    return a;
  }

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'P';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  UserProfile copyWith({
    String? name,
    DateTime? birthDate,
    double? heightCm,
    double? weightKg,
    String? sex,
    String? level,
    double? weeklyGoalKm,
    bool clearBirth = false,
    bool clearHeight = false,
    bool clearWeight = false,
    bool clearSex = false,
  }) =>
      UserProfile(
        name: name ?? this.name,
        birthDate: clearBirth ? null : (birthDate ?? this.birthDate),
        heightCm: clearHeight ? null : (heightCm ?? this.heightCm),
        weightKg: clearWeight ? null : (weightKg ?? this.weightKg),
        sex: clearSex ? null : (sex ?? this.sex),
        level: level ?? this.level,
        weeklyGoalKm: weeklyGoalKm ?? this.weeklyGoalKm,
      );

  Map<String, Object?> toJson() => {
        'name': name,
        'birthDate': birthDate?.toIso8601String(),
        'heightCm': heightCm,
        'weightKg': weightKg,
        'sex': sex,
        'level': level,
        'weeklyGoalKm': weeklyGoalKm,
      };

  static UserProfile fromJson(Map<String, Object?> j) => UserProfile(
        name: (j['name'] as String?) ?? '',
        birthDate: j['birthDate'] == null ? null : DateTime.tryParse(j['birthDate'] as String),
        heightCm: (j['heightCm'] as num?)?.toDouble(),
        weightKg: (j['weightKg'] as num?)?.toDouble(),
        sex: j['sex'] as String?,
        level: (j['level'] as String?) ?? 'Iniciante',
        weeklyGoalKm: ((j['weeklyGoalKm'] as num?) ?? 15).toDouble(),
      );
}

/// Atividade completa, com pontos, parciais e voltas.
class ActivityBundle {
  final Activity activity;
  final List<TrackPoint> points;
  final List<Split> splits;
  final List<Lap> laps;

  const ActivityBundle({
    required this.activity,
    this.points = const [],
    this.splits = const [],
    this.laps = const [],
  });
}
