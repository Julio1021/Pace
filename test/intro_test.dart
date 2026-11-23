import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pace/domain/intro_messages.dart';
import 'package:pace/domain/models.dart';
import 'package:pace/domain/stats.dart';

void main() {
  final now = DateTime(2026, 11, 23, 8, 30);
  Activity run(int daysAgo, double km) =>
      Activity(id: daysAgo, start: now.subtract(Duration(days: daysAgo)).toUtc(), distanceM: km * 1000, movingSec: (km * 330).round());

  test('tempo de leitura confortável (6 a 16 s, cresce com o texto)', () {
    const short = IntroMessage(title: 'Oi!', text: 'Bora?', tip: 'Beba água.', tipIsAdvice: true, pose: GuaraPoseHint.wave, entrance: IntroEntrance.pop);
    final long = IntroMessage(title: 'Bom dia, Júlio!', text: 'x' * 120, tip: 'y' * 80, tipIsAdvice: true, pose: GuaraPoseHint.wave, entrance: IntroEntrance.pop);
    expect(short.readingTime.inSeconds, 6);
    expect(long.readingTime.inMilliseconds, greaterThan(15000));
    expect(long.readingTime.inSeconds, lessThanOrEqualTo(16));
  });

  test('recado usa os dados reais e não repete os recentes', () {
    final runs = [run(1, 12), run(3, 5), run(9, 21)];
    final recent = <String>[];
    final seen = <String>{};
    final rnd = math.Random(3);
    for (var i = 0; i < 8; i++) {
      final m = IntroMessages.pick(
        name: 'Júlio César',
        now: now,
        runs: runs,
        rides: const [],
        weeklyGoalKm: 20,
        week: PeriodStats.of(runs.take(1).toList()),
        recent: recent,
        random: rnd,
      );
      expect(m.title, 'Bom dia, Júlio!');
      expect(seen.contains(m.tip), isFalse, reason: 'dica repetida: ${m.tip}');
      seen.add(m.tip);
      recent.insertAll(0, [m.text, m.tip]);
    }
  });

  test('sem treinos: convite para o primeiro', () {
    final m = IntroMessages.pick(
      name: 'Ana',
      now: now,
      runs: const [],
      rides: const [],
      weeklyGoalKm: 0,
      week: PeriodStats.of(const []),
      recent: const [],
    );
    expect(m.text, contains('primeiro treino'));
  });

  test('de madrugada o Guará está com sono', () {
    final m = IntroMessages.pick(
      name: 'Ana',
      now: DateTime(2026, 11, 23, 23, 30),
      runs: [run(5, 5)],
      rides: const [],
      weeklyGoalKm: 0,
      week: PeriodStats.of(const []),
      recent: const ['Faz 5 dias desde o último treino. Que tal algo leve hoje?'],
    );
    expect(m.pose, GuaraPoseHint.sleep);
    expect(m.entrance, IntroEntrance.peek);
  });
}
