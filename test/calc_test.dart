import 'package:flutter_test/flutter_test.dart';
import 'package:pace/core/format.dart';
import 'package:pace/domain/calc.dart';
import 'package:pace/domain/models.dart';

TrackPoint pt(int sec, double dist, {double? alt}) => TrackPoint(
      time: DateTime.utc(2026, 1, 1).add(Duration(seconds: sec)),
      lat: 0,
      lon: 0,
      alt: alt,
      dist: dist,
      mov: sec.toDouble(),
    );

void main() {
  group('Distância', () {
    test('1 grau de latitude ≈ 111,2 km', () {
      final d = Calc.haversine(0, 0, 1, 0);
      expect(d, closeTo(111195, 5));
    });

    test('ponto igual = 0', () {
      expect(Calc.haversine(-22.8, -45.18, -22.8, -45.18), 0);
    });
  });

  group('Filtro de GPS', () {
    final last = TrackPoint(time: DateTime.utc(2026, 1, 1, 7), lat: -22.8, lon: -45.18);

    test('precisão pior que 20 m é descartada', () {
      expect(
        GpsFilter.check(accuracy: 35, lat: -22.8001, lon: -45.18, time: last.time.add(const Duration(seconds: 1)), lastAccepted: last),
        GpsVerdict.badAccuracy,
      );
    });

    test('salto impossível (> 9 m/s) é descartado', () {
      // ~111 m em 1 s
      expect(
        GpsFilter.check(accuracy: 5, lat: -22.801, lon: -45.18, time: last.time.add(const Duration(seconds: 1)), lastAccepted: last),
        GpsVerdict.impossibleJump,
      );
    });

    test('menos de 3 m é tremulação', () {
      expect(
        GpsFilter.check(accuracy: 5, lat: -22.80001, lon: -45.18, time: last.time.add(const Duration(seconds: 1)), lastAccepted: last),
        GpsVerdict.tooClose,
      );
    });

    test('ponto normal é aceito', () {
      // ~3,3 m/s
      expect(
        GpsFilter.check(accuracy: 6, lat: -22.80003, lon: -45.18, time: last.time.add(const Duration(seconds: 1)), lastAccepted: last),
        GpsVerdict.accept,
      );
    });
  });

  group('Pausa automática', () {
    test('pausa após 8 s abaixo de 0,8 m/s e retoma acima de 1,2 m/s', () {
      final ap = AutoPause();
      final t0 = DateTime.utc(2026);
      expect(ap.update(t0, 3), isFalse);
      expect(ap.update(t0.add(const Duration(seconds: 1)), 0.3), isFalse);
      expect(ap.update(t0.add(const Duration(seconds: 8)), 0.3), isFalse);
      expect(ap.update(t0.add(const Duration(seconds: 9)), 0.2), isTrue);
      expect(ap.update(t0.add(const Duration(seconds: 10)), 1.0), isTrue);
      expect(ap.update(t0.add(const Duration(seconds: 11)), 1.5), isFalse);
    });
  });

  group('Pace', () {
    test('arredonda ao segundo mais próximo', () {
      expect(Fmt.pace(293.88), '4:54');
      expect(Fmt.pace(305.53), '5:06');
      expect(Fmt.pace(299.6), '5:00');
      expect(Fmt.pace(null), '—');
    });

    test('janela de 30 s', () {
      final w = PaceWindow();
      for (var s = 0; s <= 60; s++) {
        w.add(s.toDouble(), s * 3.5);
      }
      expect(w.current, closeTo(1000 / 3.5, 1));
    });
  });

  group('Parciais por km', () {
    test('velocidade constante de 4 m/s em 2,5 km', () {
      final pts = [for (var s = 0; s <= 625; s++) pt(s, s * 4.0)];
      final sp = Calc.splits(pts);
      expect(sp.length, 3);
      expect(sp[0].sec, closeTo(250, 0.01));
      expect(sp[1].sec, closeTo(250, 0.01));
      expect(sp[2].distM, closeTo(500, 0.01));
      expect(sp[2].sec, closeTo(125, 0.01));
      expect(Calc.bestKm(sp), 250);
    });

    test('interpola o tempo exato de passagem', () {
      final pts = [pt(0, 0), pt(100, 900), pt(200, 1100)];
      final sp = Calc.splits(pts);
      // 1000 m está no meio entre 900 e 1100 → 150 s
      expect(sp.first.sec, closeTo(150, 0.01));
    });
  });

  group('Elevação', () {
    test('ignora oscilações menores que 2 m', () {
      final alts = <double?>[for (var i = 0; i < 50; i++) 100 + (i.isEven ? 0.5 : -0.5)];
      final e = Calc.elevation(alts);
      expect(e.gain, 0);
      expect(e.loss, 0);
    });

    test('subida de 20 m e descida de 10 m', () {
      final alts = <double?>[
        for (var i = 0; i <= 20; i++) 100.0 + i,
        for (var i = 1; i <= 10; i++) 120.0 - i,
      ];
      final e = Calc.elevation(alts);
      // A suavização arredonda o pico; a histerese descarta resto menor que 2 m.
      expect(e.gain, inInclusiveRange(15, 20.5));
      expect(e.loss, inInclusiveRange(4, 10.5));
    });
  });

  test('calorias = peso × km', () {
    expect(Calc.calories(70, 10000), 700);
  });

  test('formatação', () {
    expect(Fmt.km(13034.87), '13,03');
    expect(Fmt.duration(3831), '1:03:51');
    expect(Fmt.duration(3787), '1:03:07');
    expect(Fmt.duration(312), '5:12');
  });
}
