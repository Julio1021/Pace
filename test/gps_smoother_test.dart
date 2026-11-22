import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pace/domain/calc.dart';
import 'package:pace/domain/models.dart';

void main() {
  test('suavização corta o zigue-zague sem perder a distância real', () {
    // 400 m em linha reta a 3 m/s, com ruído de ±6 m para os lados.
    final t0 = DateTime.utc(2026, 1, 1, 6);
    final rnd = math.Random(7);
    const lat0 = -22.8, lon0 = -45.19;
    const mPerDegLat = 111320.0;
    final sm = GpsSmoother();
    double raw = 0, smooth = 0;
    double? pl, plo, sl, slo;
    DateTime? lastT;
    for (var i = 0; i <= 133; i++) {
      final north = i * 3.0;
      final side = (rnd.nextDouble() * 2 - 1) * 6;
      final lat = lat0 + north / mPerDegLat;
      final lon = lon0 + side / (mPerDegLat * math.cos(lat0 * math.pi / 180));
      final time = t0.add(Duration(seconds: i));
      final s = sm.update(lat, lon, 8, time);
      if (pl != null) raw += Calc.haversine(pl, plo!, lat, lon);
      pl = lat;
      plo = lon;
      // Mesmo caminho do gravador: filtro + regras de aceite.
      final v = GpsFilter.check(
        accuracy: 8,
        lat: s.lat,
        lon: s.lon,
        time: time,
        lastAccepted: sl == null ? null : TrackPoint(time: lastT!, lat: sl, lon: slo!, dist: 0, mov: 0),
      );
      if (v != GpsVerdict.accept) continue;
      if (sl != null) smooth += Calc.haversine(sl, slo!, s.lat, s.lon);
      sl = s.lat;
      slo = s.lon;
      lastT = time;
    }
    expect(raw, greaterThan(550)); // o ruído infla muito a distância bruta
    expect((smooth - 400).abs(), lessThan((raw - 400).abs()));
    expect(smooth, closeTo(400, 25));
  });

  test('parado com sinal ruim não soma distância', () {
    final last = GpsFilter.check(accuracy: 15, lat: -22.8, lon: -45.19, time: DateTime.utc(2026), lastAccepted: null);
    expect(last, GpsVerdict.accept);
  });
}
