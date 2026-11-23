import 'dart:math' as math;

import '../domain/calc.dart';
import '../domain/models.dart';

/// Grava os pontos de GPS de forma compacta e SEM PERDA:
/// - uma lista por campo (em vez de repetir os nomes em cada ponto);
/// - tempo como diferença do ponto anterior;
/// - números com poucas casas decimais viram inteiros (diferença do anterior),
///   mas só quando a volta é exata, bit a bit; senão o valor vai inteiro;
/// - distância e tempo em movimento são omitidos quando o recálculo dá
///   exatamente o mesmo resultado (corridas importadas).
class PointCodec {
  static Map<String, Object?> encode(List<TrackPoint> pts) {
    final n = pts.length;
    final t = [for (final p in pts) p.time.toUtc().millisecondsSinceEpoch];
    final out = <String, Object?>{
      'n': n,
      't': [for (var i = 0; i < n; i++) i == 0 ? t[0] : t[i] - t[i - 1]],
      'lat': _num([for (final p in pts) p.lat]),
      'lon': _num([for (final p in pts) p.lon]),
      'alt': _num([for (final p in pts) p.alt]),
      'acc': _num([for (final p in pts) p.accuracy]),
      'speed': _num([for (final p in pts) p.speed]),
      'hr': _int([for (final p in pts) p.hr]),
      'cad': _int([for (final p in pts) p.cad]),
      'paused': [for (var i = 0; i < n; i++) if (pts[i].paused) i],
    };
    final calc = Calc.accumulate(pts);
    var distSame = true;
    var movSame = true;
    for (var i = 0; i < n; i++) {
      if (calc[i].dist != pts[i].dist) distSame = false;
      if (calc[i].mov != pts[i].mov) movSame = false;
    }
    out['dist'] = distSame ? 'calc' : _num([for (final p in pts) p.dist]);
    out['mov'] = movSame ? 'calc' : _num([for (final p in pts) p.mov]);
    return out;
  }

  static List<TrackPoint> decode(Map<String, Object?> m) {
    final n = (m['n'] as num).toInt();
    final dt = (m['t'] as List).cast<num>();
    final lat = _unNum(m['lat'], n);
    final lon = _unNum(m['lon'], n);
    final alt = _unNum(m['alt'], n);
    final acc = _unNum(m['acc'], n);
    final speed = _unNum(m['speed'], n);
    final hr = _unInt(m['hr'], n);
    final cad = _unInt(m['cad'], n);
    final paused = {for (final i in (m['paused'] as List? ?? const [])) (i as num).toInt()};
    final distCalc = m['dist'] == 'calc';
    final movCalc = m['mov'] == 'calc';
    final dist = distCalc ? null : _unNum(m['dist'], n);
    final mov = movCalc ? null : _unNum(m['mov'], n);
    var time = 0;
    var pts = <TrackPoint>[
      for (var i = 0; i < n; i++)
        TrackPoint(
          time: DateTime.fromMillisecondsSinceEpoch(time += dt[i].toInt(), isUtc: true),
          lat: lat[i]!,
          lon: lon[i]!,
          alt: alt[i],
          accuracy: acc[i],
          speed: speed[i],
          hr: hr[i],
          cad: cad[i],
          dist: dist?[i] ?? 0,
          mov: mov?[i] ?? 0,
          paused: paused.contains(i),
        ),
    ];
    if (distCalc || movCalc) {
      final calc = Calc.accumulate(pts);
      pts = [
        for (var i = 0; i < n; i++) pts[i].withProgress(distCalc ? calc[i].dist : pts[i].dist, movCalc ? calc[i].mov : pts[i].mov),
      ];
    }
    return pts;
  }

  /// Números: {"s": casas, "d": [diferenças inteiras]} se for exato; senão {"v": [valores]}.
  static Object? _num(List<double?> v) {
    if (v.every((x) => x == null)) return null;
    for (var s = 0; s <= 9; s++) {
      final p = math.pow(10, s).toDouble();
      var ok = true;
      for (final x in v) {
        if (x == null) continue;
        final r = (x * p).round();
        if (r.abs() > 9007199254740991 ~/ 2 || r / p != x) {
          ok = false;
          break;
        }
      }
      if (!ok) continue;
      var prev = 0;
      final d = <int?>[];
      for (final x in v) {
        if (x == null) {
          d.add(null);
          continue;
        }
        final r = (x * p).round();
        d.add(r - prev);
        prev = r;
      }
      return {'s': s, 'd': d};
    }
    return {'v': v};
  }

  static List<double?> _unNum(Object? o, int n) {
    if (o == null) return List<double?>.filled(n, null);
    final m = o as Map;
    if (m['v'] != null) return [for (final x in m['v'] as List) (x as num?)?.toDouble()];
    final p = math.pow(10, (m['s'] as num).toInt()).toDouble();
    var prev = 0;
    return [
      for (final x in m['d'] as List)
        if (x == null) null else (prev += (x as num).toInt()) / p,
    ];
  }

  static Object? _int(List<int?> v) {
    if (v.every((x) => x == null)) return null;
    var prev = 0;
    final d = <int?>[];
    for (final x in v) {
      if (x == null) {
        d.add(null);
      } else {
        d.add(x - prev);
        prev = x;
      }
    }
    return d;
  }

  static List<int?> _unInt(Object? o, int n) {
    if (o == null) return List<int?>.filled(n, null);
    var prev = 0;
    return [
      for (final x in o as List)
        if (x == null) null else prev += (x as num).toInt(),
    ];
  }
}
