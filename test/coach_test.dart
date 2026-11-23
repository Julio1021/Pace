import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pace/domain/coach.dart';

void main() {
  test('estilo discreto e desligado não falam frases', () {
    for (final s in [CoachStyle.discreet, CoachStyle.off]) {
      final c = Coach(style: s);
      expect(c.onStart(), isNull);
      expect(c.onKm(1, 400, splitSec: 400), isNull);
      expect(c.onFinish(3000), isNull);
    }
  });

  test('corrida livre: 1º km e depois a cada 2 km, com 60 s de intervalo', () {
    final c = Coach(style: CoachStyle.energetic, random: math.Random(1));
    expect(c.onStart(), isNotNull);
    expect(c.onKm(1, 360, splitSec: 360), isNotNull);
    expect(c.onKm(2, 720, splitSec: 360), isNull);
    expect(c.onKm(3, 1080, splitSec: 360, avgPrevSec: 360), isNotNull);
    expect(c.onKm(4, 1440, splitSec: 360, avgPrevSec: 360), isNull);
    // Menos de 60 s depois da última frase: não fala.
    expect(c.onResume(1100), isNull);
  });

  test('ritmo mais rápido que a média gera a frase de ritmo', () {
    final c = Coach(style: CoachStyle.energetic, random: math.Random(2));
    c.onKm(1, 360, splitSec: 360);
    final p = c.onKm(3, 1000, splitSec: 330, avgPrevSec: 360);
    expect(CoachPhrases.energetic[CoachMoment.faster], contains(p));
  });

  test('com meta: 25, 50, 75 e 90% uma vez cada, sem repetir frases', () {
    final c = Coach(style: CoachStyle.energetic, hasGoal: true, random: math.Random(3));
    final said = <String>[];
    var mov = 0.0;
    for (var pct = 0.0; pct < 1.0; pct += 0.01) {
      mov += 70;
      final p = c.onProgress(pct, mov);
      if (p != null) said.add(p);
    }
    expect(said.length, 4);
    expect(said.toSet().length, 4);
  });

  test('marco atrasado não dispara os anteriores em sequência', () {
    final c = Coach(style: CoachStyle.gentle, hasGoal: true);
    expect(c.onProgress(0.8, 1000), isNotNull); // 75%
    expect(c.onProgress(0.81, 1100), isNull); // 25 e 50% já marcados
  });

  test('avisos a cada 2 km: frase no 1º aviso e em todos os seguintes', () {
    final c = Coach(style: CoachStyle.energetic, random: math.Random(4));
    expect(c.onKm(2, 700, splitSec: 350, every: 2), isNotNull);
    expect(c.onKm(4, 1400, splitSec: 350, avgPrevSec: 350, every: 2), isNotNull);
    expect(c.onKm(6, 2100, splitSec: 350, avgPrevSec: 350, every: 2), isNotNull);
  });
}
