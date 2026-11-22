import 'dart:math' as math;

import 'models.dart';

/// Regras de cálculo do PACE. Funções puras, sem Flutter, cobertas por testes.
class Calc {
  static const earthRadiusM = 6371008.8;

  /// Distância geodésica (Haversine) em metros.
  static double haversine(double lat1, double lon1, double lat2, double lon2) {
    final p1 = lat1 * math.pi / 180;
    final p2 = lat2 * math.pi / 180;
    final dp = (lat2 - lat1) * math.pi / 180;
    final dl = (lon2 - lon1) * math.pi / 180;
    final a = math.sin(dp / 2) * math.sin(dp / 2) +
        math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
    return 2 * earthRadiusM * math.asin(math.min(1, math.sqrt(a)));
  }

  /// Calorias estimadas: 1,0 kcal × peso (kg) × distância (km).
  static double calories(double weightKg, double distanceM) => weightKg * distanceM / 1000;

  /// Pace (s/km) a partir de segundos e metros. Nulo se a distância for pequena demais.
  static double? pace(double seconds, double meters) {
    if (meters < 10 || seconds <= 0) return null;
    return seconds / (meters / 1000);
  }

  /// Parciais por km, com o tempo exato de passagem interpolado entre os pontos vizinhos.
  /// O último km parcial entra com a distância real (se tiver pelo menos 10 m).
  static List<Split> splits(List<TrackPoint> pts) {
    final out = <Split>[];
    if (pts.length < 2) return out;
    var nextKm = 1000.0;
    var lastCrossMov = pts.first.mov;
    for (var i = 1; i < pts.length; i++) {
      final a = pts[i - 1];
      final b = pts[i];
      while (b.dist >= nextKm && b.dist > a.dist) {
        final f = ((nextKm - a.dist) / (b.dist - a.dist)).clamp(0.0, 1.0);
        final crossMov = a.mov + (b.mov - a.mov) * f;
        out.add(Split(km: out.length + 1, distM: 1000, sec: crossMov - lastCrossMov));
        lastCrossMov = crossMov;
        nextKm += 1000;
      }
    }
    final last = pts.last;
    final rest = last.dist - (nextKm - 1000);
    if (rest >= 10) {
      out.add(Split(km: out.length + 1, distM: rest, sec: last.mov - lastCrossMov));
    }
    return out;
  }

  /// Melhor km completo (s), entre as parciais.
  static int? bestKm(List<Split> splits) {
    double? best;
    for (final s in splits) {
      if (s.distM < 999 || s.sec <= 0) continue;
      if (best == null || s.sec < best) best = s.sec;
    }
    return best?.round();
  }

  /// Ganho e perda de elevação: altitude suavizada (média móvel de 5 pontos)
  /// e soma só acima de 2 m de diferença acumulada (histerese).
  static ({double gain, double loss}) elevation(List<double?> altitudes) {
    final alts = altitudes.whereType<double>().toList();
    if (alts.length < 2) return (gain: 0, loss: 0);
    final smooth = movingAverage(alts, 5);
    var gain = 0.0;
    var loss = 0.0;
    var ref = smooth.first;
    for (final a in smooth.skip(1)) {
      if (a - ref >= 2) {
        gain += a - ref;
        ref = a;
      } else if (ref - a >= 2) {
        loss += ref - a;
        ref = a;
      }
    }
    return (gain: gain, loss: loss);
  }

  static List<double> movingAverage(List<double> v, int window) {
    if (v.isEmpty) return const [];
    final half = window ~/ 2;
    final out = List<double>.filled(v.length, 0);
    for (var i = 0; i < v.length; i++) {
      final from = math.max(0, i - half);
      final to = math.min(v.length - 1, i + half);
      var sum = 0.0;
      for (var j = from; j <= to; j++) {
        sum += v[j];
      }
      out[i] = sum / (to - from + 1);
    }
    return out;
  }

  /// Recalcula distância e tempo em movimento acumulados de uma trilha importada.
  /// Trechos com velocidade impossível (> 12 m/s) não somam distância e
  /// intervalos maiores que 2 min não somam tempo.
  static List<TrackPoint> accumulate(List<TrackPoint> pts) {
    if (pts.isEmpty) return pts;
    final out = <TrackPoint>[pts.first.withProgress(0, 0)];
    var dist = 0.0;
    var mov = 0.0;
    for (var i = 1; i < pts.length; i++) {
      final a = pts[i - 1];
      final b = pts[i];
      final dt = b.time.difference(a.time).inMilliseconds / 1000.0;
      final d = haversine(a.lat, a.lon, b.lat, b.lon);
      if (dt > 0 && dt <= 120) {
        if (d / dt <= 12) dist += d;
        mov += dt;
      }
      out.add(b.withProgress(dist, mov));
    }
    return out;
  }

  /// Trajeto simplificado para miniaturas: até [maxPoints] pontos, 5 casas decimais.
  static String preview(List<TrackPoint> pts, {int maxPoints = 80}) {
    final moving = pts.where((p) => !p.paused).toList();
    if (moving.length < 2) return '';
    final step = math.max(1, (moving.length / maxPoints).ceil());
    final buf = StringBuffer();
    for (var i = 0; i < moving.length; i += step) {
      if (buf.isNotEmpty) buf.write(';');
      buf.write('${moving[i].lat.toStringAsFixed(5)},${moving[i].lon.toStringAsFixed(5)}');
    }
    final last = moving.last;
    buf.write(';${last.lat.toStringAsFixed(5)},${last.lon.toStringAsFixed(5)}');
    return buf.toString();
  }

  /// Série de pace (s/km) ao longo da distância (km), em janelas de 30 s de movimento,
  /// com uma amostra a cada [stepM] metros. Valores fora de 2:00–20:00/km são descartados.
  static List<({double km, double pace})> paceSeries(List<TrackPoint> pts, {double stepM = 100}) {
    final out = <({double km, double pace})>[];
    if (pts.length < 3) return out;
    var next = stepM;
    var j = 0;
    for (var i = 1; i < pts.length; i++) {
      final b = pts[i];
      if (b.dist < next) continue;
      next = (b.dist ~/ stepM + 1) * stepM;
      while (j < i && pts[j].mov < b.mov - 30) {
        j++;
      }
      final a = pts[j == i ? i - 1 : j];
      final p = pace(b.mov - a.mov, b.dist - a.dist);
      if (p != null && p >= 120 && p <= 1200) out.add((km: b.dist / 1000, pace: p));
    }
    return out;
  }

  /// Altitude suavizada ao longo da distância (km).
  static List<({double km, double alt})> altitudeSeries(List<TrackPoint> pts, {int maxPoints = 300}) {
    final withAlt = pts.where((p) => p.alt != null).toList();
    if (withAlt.length < 2) return const [];
    final smooth = movingAverage(withAlt.map((p) => p.alt!).toList(), 5);
    final step = math.max(1, (withAlt.length / maxPoints).ceil());
    final out = <({double km, double alt})>[];
    for (var i = 0; i < withAlt.length; i += step) {
      out.add((km: withAlt[i].dist / 1000, alt: smooth[i]));
    }
    return out;
  }

  /// Frequência cardíaca média e máxima (ignora zeros).
  static ({int? avg, int? max}) heartRate(List<TrackPoint> pts) {
    final hr = pts.map((p) => p.hr).whereType<int>().where((h) => h > 30 && h < 250).toList();
    if (hr.isEmpty) return (avg: null, max: null);
    final avg = hr.reduce((a, b) => a + b) / hr.length;
    return (avg: avg.round(), max: hr.reduce(math.max));
  }

  static int? avgCadence(List<TrackPoint> pts) {
    final c = pts.map((p) => p.cad).whereType<int>().where((v) => v > 0).toList();
    if (c.isEmpty) return null;
    return (c.reduce((a, b) => a + b) / c.length).round();
  }
}

/// Resultado do filtro de GPS para um ponto novo.
enum GpsVerdict { accept, badAccuracy, impossibleJump, tooClose }

/// Filtro de GPS: precisão pior que 20 m é descartada; um ponto que implique
/// mais de 9 m/s (32 km/h) em relação ao último aceito é descartado; deslocamentos
/// menores que 3 m são tremulação (parado).
class GpsFilter {
  /// Sinal considerado bom (aviso e confirmação para iniciar).
  static const maxAccuracyM = 20.0;

  /// Pontos entre 20 e 30 m ainda entram, com peso menor no filtro de suavização.
  static const maxInputAccuracyM = 30.0;
  static const maxSpeedMps = 9.0;
  static const minMoveM = 3.0;

  static GpsVerdict check({
    required double accuracy,
    required double lat,
    required double lon,
    required DateTime time,
    TrackPoint? lastAccepted,
  }) {
    if (accuracy > maxInputAccuracyM || !accuracy.isFinite) return GpsVerdict.badAccuracy;
    final last = lastAccepted;
    if (last == null) return accuracy > maxAccuracyM ? GpsVerdict.badAccuracy : GpsVerdict.accept;
    final d = Calc.haversine(last.lat, last.lon, lat, lon);
    final dt = time.difference(last.time).inMilliseconds / 1000.0;
    if (dt <= 0) return GpsVerdict.tooClose;
    if (d / dt > maxSpeedMps) return GpsVerdict.impossibleJump;
    // Parado, o GPS "passeia" alguns metros; o mínimo cresce com a imprecisão.
    if (d < math.max(minMoveM, accuracy * 0.4)) return GpsVerdict.tooClose;
    return GpsVerdict.accept;
  }

  /// Qualidade do sinal para a tela de preparação.
  static String quality(double? accuracy) {
    if (accuracy == null) return 'Procurando sinal…';
    if (accuracy <= 8) return 'Ótimo';
    if (accuracy <= 20) return 'Bom';
    return 'Fraco';
  }
}

/// Filtro de Kalman simples para latitude/longitude: suaviza o zigue-zague
/// do GPS dando mais peso aos pontos precisos. Evita somar distância
/// fantasma em ruas com prédios ou árvores.
class GpsSmoother {
  /// Quanto a posição pode mudar por segundo (m/s) — corrida rápida, com folga.
  static const q = 3.0;
  double? _lat, _lon;
  double _var = -1;
  DateTime? _t;

  void reset() {
    _var = -1;
    _lat = _lon = null;
    _t = null;
  }

  ({double lat, double lon}) update(double lat, double lon, double accuracy, DateTime time) {
    final acc = math.max(accuracy, 1.0);
    if (_var < 0 || _lat == null) {
      _lat = lat;
      _lon = lon;
      _var = acc * acc;
      _t = time;
      return (lat: lat, lon: lon);
    }
    final dt = time.difference(_t!).inMilliseconds / 1000.0;
    if (dt > 0) {
      _var += dt * q * q;
      _t = time;
    }
    final k = _var / (_var + acc * acc);
    _lat = _lat! + k * (lat - _lat!);
    _lon = _lon! + k * (lon - _lon!);
    _var = (1 - k) * _var;
    return (lat: _lat!, lon: _lon!);
  }
}

/// Pausa automática: pausa quando a velocidade fica abaixo de 0,8 m/s por 8 s;
/// retoma acima de 1,2 m/s.
class AutoPause {
  static const pauseBelow = 0.8;
  static const resumeAbove = 1.2;
  static const pauseAfter = Duration(seconds: 8);

  bool paused = false;
  DateTime? _slowSince;

  /// Atualiza com a velocidade atual e devolve se está em pausa automática.
  bool update(DateTime time, double speedMps) {
    if (paused) {
      if (speedMps > resumeAbove) {
        paused = false;
        _slowSince = null;
      }
      return paused;
    }
    if (speedMps < pauseBelow) {
      _slowSince ??= time;
      if (time.difference(_slowSince!) >= pauseAfter) paused = true;
    } else {
      _slowSince = null;
    }
    return paused;
  }

  void reset() {
    paused = false;
    _slowSince = null;
  }
}

/// Pace atual numa janela móvel dos últimos 30 s de movimento.
class PaceWindow {
  static const window = 30.0;
  final _samples = <({double mov, double dist})>[];

  void add(double mov, double dist) {
    _samples.add((mov: mov, dist: dist));
    while (_samples.length > 2 && _samples[1].mov <= mov - window) {
      _samples.removeAt(0);
    }
  }

  void clear() => _samples.clear();

  /// s/km, ou nulo se andou menos de 20 m na janela.
  double? get current {
    if (_samples.length < 2) return null;
    final a = _samples.first;
    final b = _samples.last;
    final d = b.dist - a.dist;
    if (d < 20) return null;
    return Calc.pace(b.mov - a.mov, d);
  }
}
