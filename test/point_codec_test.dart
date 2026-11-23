import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pace/data/point_codec.dart';
import 'package:pace/domain/models.dart';

void main() {
  test('pontos gravados ao vivo (valores quebrados, nulos, pausas) voltam idênticos', () {
    final r = math.Random(7);
    var lat = -22.8 + r.nextDouble() * 1e-3, lon = -45.2, dist = 0.0, mov = 0.0;
    final pts = <TrackPoint>[];
    var t = DateTime.utc(2026, 11, 23, 7);
    for (var i = 0; i < 1500; i++) {
      t = t.add(Duration(milliseconds: 950 + r.nextInt(120)));
      lat += r.nextDouble() * 2e-5;
      lon += r.nextDouble() * 2e-5;
      final paused = i > 600 && i < 640;
      if (!paused) {
        dist += 3 * r.nextDouble();
        mov += 1.0 + r.nextDouble() / 10;
      }
      pts.add(TrackPoint(
        time: t,
        lat: lat,
        lon: lon,
        alt: i % 50 == 0 ? null : 540 + r.nextDouble() * 10,
        accuracy: (r.nextDouble() * 12).toDouble(),
        speed: i % 7 == 0 ? null : r.nextDouble() * 4,
        hr: i < 100 ? null : 120 + r.nextInt(50),
        cad: null,
        dist: dist,
        mov: mov,
        paused: paused,
      ));
    }
    final packed = jsonDecode(jsonEncode(PointCodec.encode(pts))) as Map<String, Object?>;
    final back = PointCodec.decode(packed);
    expect(back.length, pts.length);
    for (var i = 0; i < pts.length; i++) {
      expect(back[i].toMap(0, i), pts[i].toMap(0, i), reason: 'ponto $i');
    }
  });

  test('coordenadas com poucas casas viram inteiros, sem perda', () {
    final pts = [
      for (var i = 0; i < 50; i++)
        TrackPoint(time: DateTime.utc(2026, 1, 1).add(Duration(seconds: i)), lat: -22.8000001 + i * 1e-5, lon: -45.1234567, alt: 540.5)
    ];
    final m = PointCodec.encode(pts);
    expect((m['alt'] as Map)['s'], 1);
    final back = PointCodec.decode(jsonDecode(jsonEncode(m)) as Map<String, Object?>);
    for (var i = 0; i < pts.length; i++) {
      expect(back[i].toMap(0, i), pts[i].toMap(0, i));
    }
  });
}
