import 'package:flutter_test/flutter_test.dart';
import 'package:pace/domain/achievements.dart';
import 'package:pace/domain/goals.dart';
import 'package:pace/domain/models.dart';
import 'package:pace/domain/plans.dart';
import 'package:pace/domain/records.dart';
import 'package:pace/domain/reminders.dart';

/// Pontos de uma corrida de [km] com pace constante [pace] s/km, com um trecho mais rápido opcional.
List<TrackPoint> run(double km, double pace, {double fastFromKm = -1, double fastKm = 0, double fastPace = 0}) {
  final pts = <TrackPoint>[];
  var d = 0.0, t = 0.0;
  final t0 = DateTime.utc(2026, 1, 1, 7);
  while (d < km * 1000) {
    pts.add(TrackPoint(time: t0.add(Duration(milliseconds: (t * 1000).round())), lat: 0, lon: 0, dist: d, mov: t));
    final inFast = d >= fastFromKm * 1000 && d < (fastFromKm + fastKm) * 1000;
    final p = inFast ? fastPace : pace;
    d += 10;
    t += p / 100;
  }
  pts.add(TrackPoint(time: t0.add(Duration(seconds: t.round())), lat: 0, lon: 0, dist: d, mov: t));
  return pts;
}

Activity act(int id, DateTime start, double km, int sec, {double elev = 0}) =>
    Activity(id: id, start: start.toUtc(), distanceM: km * 1000, movingSec: sec, elapsedSec: sec, elevGain: elev);

void main() {
  group('melhores esforços', () {
    test('acha o trecho mais rápido no meio da corrida', () {
      final e = bestEfforts(run(8, 360, fastFromKm: 2, fastKm: 5, fastPace: 300));
      expect(e[1000], closeTo(300, 1));
      expect(e[5000], closeTo(1500, 2));
      expect(e.containsKey(10000), isFalse);
    });

    test('distância exata conta', () {
      final e = bestEfforts(run(5, 330));
      expect(e[5000], closeTo(1650, 2));
    });
  });

  group('recordes', () {
    final acts = [
      act(1, DateTime(2026, 3, 2, 7), 5.2, 1800),
      act(2, DateTime(2026, 3, 4, 7), 10.1, 3700, elev: 80),
      act(3, DateTime(2026, 3, 20, 7), 6, 1900),
    ];
    final efforts = {
      1: {1000: 330, 5000: 1720},
      2: {1000: 340, 5000: 1790, 10000: 3650},
      3: {1000: 300, 5000: 1600},
    };

    test('calcula e encontra quem detém', () {
      final r = Records.compute(acts, efforts);
      expect(r.byKey('effort_5000')!.activityId, 3);
      expect(r.byKey('effort_10000')!.value, 3650);
      expect(r.byKey('longestRun')!.activityId, 2);
      expect(r.byKey('biggestWeek')!.value, closeTo(15300, 1));
    });

    test('recordes batidos pela corrida', () {
      final b = Records.brokenBy(3, acts, efforts);
      final keys = b.map((x) => x.now.key).toSet();
      expect(keys, containsAll(['effort_1000', 'effort_5000']));
      final five = b.firstWhere((x) => x.now.key == 'effort_5000');
      expect(five.before!.value, 1720);
      expect(keys.contains('effort_10000'), isFalse);
    });
  });

  group('conquistas', () {
    test('desbloqueia na corrida certa e mostra progresso', () {
      final acts = [
        for (var i = 0; i < 12; i++) act(i + 1, DateTime(2026, 1, 5 + i * 7, i == 3 ? 5 : 18), i == 11 ? 10.5 : 5.0, 1700),
      ];
      final b = {for (final x in computeAchievements(acts, {12: {5000: 1500}}, weeklyGoalKm: 5)) x.id: x};
      expect(b['first_run']!.activityId, 1);
      expect(b['runs_10']!.activityId, 10);
      expect(b['dist_10k']!.activityId, 12);
      expect(b['early_bird']!.activityId, 4);
      expect(b['streak_4']!.activityId, 4);
      expect(b['streak_12']!.activityId, 12);
      expect(b['sub30_5k']!.unlocked, isTrue);
      expect(b['total_100']!.unlocked, isFalse);
      expect(b['total_100']!.progress, closeTo(65.5 / 100, 0.01));
      expect(b['goal_week_1']!.unlocked, isTrue);
    });
  });

  group('metas', () {
    test('previsão no ritmo atual', () {
      final now = DateTime(2026, 4, 16, 12); // metade de abril
      final acts = [act(1, DateTime(2026, 4, 3), 20, 7200), act(2, DateTime(2026, 4, 10), 20, 7200)];
      final g = GoalStatus.of(GoalPeriod.month, 100, acts, now);
      expect(g.doneKm, 40);
      expect(g.projectedKm, closeTo(80, 6));
      expect(g.leftKm, 60);
      expect(g.done, isFalse);
    });
  });

  group('planos', () {
    test('todos os planos têm treinos em todas as semanas', () {
      for (final p in TrainingPlan.all) {
        expect({for (final s in p.sessions) s.week}.length, p.weeks, reason: p.id);
        expect(p.sessions.last.type, 'Prova', reason: p.id);
      }
    });

    test('marca treinos automaticamente em ordem', () {
      final ap = ActivePlan(planId: 'rumo10k', start: DateTime(2026, 5, 4));
      final acts = [
        act(1, DateTime(2026, 5, 3, 7), 10, 3600), // antes do início: não conta
        act(2, DateTime(2026, 5, 5, 7), 3.5, 1300), // 4 km × 80% = 3,2: conta
        act(3, DateTime(2026, 5, 7, 7), 2, 900), // treino de 30 min: 15 min não conta
        act(4, DateTime(2026, 5, 9, 7), 6, 2000), // 33 min: conta para o treino de 30 min
      ];
      final m = ap.autoMark(acts);
      expect(m.done, {0: 2, 1: 4});
      expect(m.nextIndex, 2);
    });

    test('salva e lê', () {
      final ap = ActivePlan(planId: 'meia', start: DateTime(2026, 6, 1), done: {0: 5, 1: 0});
      final back = ActivePlan.fromJson(ap.toJson());
      expect(back!.planId, 'meia');
      expect(back.start, DateTime(2026, 6, 1));
      expect(back.done, {0: 5, 1: 0});
    });
  });

  group('lembretes', () {
    test('agenda nos dias escolhidos, pula hoje se já correu', () {
      final now = DateTime(2026, 11, 24, 8); // terça
      final acts = [act(1, DateTime(2026, 11, 24, 6), 5, 1800)];
      final notes = planReminders(
        activities: acts,
        s: const ReminderSettings(hour: 18, days: {DateTime.tuesday, DateTime.thursday}),
        weeklyGoalKm: 8,
        now: now,
      );
      final rem = notes.where((n) => n.id < 200).toList();
      expect(rem.first.at, DateTime(2026, 11, 26, 18));
      expect(rem.length, 4);
      final nudge = notes.where((n) => n.id >= 200 && n.id < 300).toList();
      expect(nudge.length, 2);
      expect(nudge.first.text, contains('3,0 km'));
      final sum = notes.firstWhere((n) => n.id == 300);
      expect(sum.at, DateTime(2026, 11, 29, 20));
      expect(sum.text, contains('1 corrida'));
    });

    test('sugere dias e horário do histórico', () {
      final now = DateTime(2026, 11, 24);
      final acts = [
        for (var i = 0; i < 8; i++) act(i, DateTime(2026, 11, 2 + i * 7, 7, 10), 5, 1800), // segundas 7:10
        for (var i = 0; i < 6; i++) act(20 + i, DateTime(2026, 11, 4 + i * 7, 7), 5, 1800), // quartas
      ];
      final s = ReminderSettings.suggested(acts, now);
      expect(s.days, contains(DateTime.monday));
      expect(s.days, contains(DateTime.wednesday));
      expect('${s.hour}:${s.minute}', '6:30');
    });
  });
}
