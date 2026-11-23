import 'models.dart';
import 'plans.dart';
import 'stats.dart';

/// Preferências das notificações agendadas.
class ReminderSettings {
  final bool reminder;
  final int hour;
  final int minute;
  final Set<int> days; // DateTime.monday..sunday
  final bool goalNudge;
  final bool weeklySummary;

  const ReminderSettings({
    this.reminder = true,
    this.hour = 18,
    this.minute = 0,
    this.days = const {DateTime.tuesday, DateTime.thursday, DateTime.saturday},
    this.goalNudge = true,
    this.weeklySummary = true,
  });

  ReminderSettings copyWith({bool? reminder, int? hour, int? minute, Set<int>? days, bool? goalNudge, bool? weeklySummary}) =>
      ReminderSettings(
        reminder: reminder ?? this.reminder,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
        days: days ?? this.days,
        goalNudge: goalNudge ?? this.goalNudge,
        weeklySummary: weeklySummary ?? this.weeklySummary,
      );

  Map<String, Object?> toJson() => {
        'reminder': reminder,
        'hour': hour,
        'minute': minute,
        'days': days.toList()..sort(),
        'goalNudge': goalNudge,
        'weeklySummary': weeklySummary,
      };

  static ReminderSettings fromJson(Map<String, dynamic> j) => ReminderSettings(
        reminder: j['reminder'] != false,
        hour: (j['hour'] as num?)?.toInt() ?? 18,
        minute: (j['minute'] as num?)?.toInt() ?? 0,
        days: {for (final d in (j['days'] as List? ?? const [2, 4, 6])) (d as num).toInt()},
        goalNudge: j['goalNudge'] != false,
        weeklySummary: j['weeklySummary'] != false,
      );

  /// Sugestão a partir do histórico: os 3 dias da semana em que você mais corre
  /// e 30 min antes do seu horário mais comum (últimos 90 dias).
  static ReminderSettings suggested(List<Activity> acts, DateTime now) {
    final recent = acts.where((a) => now.difference(a.start.toLocal()).inDays <= 90).toList();
    if (recent.length < 3) return const ReminderSettings();
    final byDay = <int, int>{};
    final minutes = <int>[];
    for (final a in recent) {
      final l = a.start.toLocal();
      byDay[l.weekday] = (byDay[l.weekday] ?? 0) + 1;
      minutes.add(l.hour * 60 + l.minute);
    }
    final days = (byDay.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(3).map((e) => e.key).toSet();
    minutes.sort();
    var m = minutes[minutes.length ~/ 2] - 30;
    if (m < 0) m += 24 * 60;
    m = (m ~/ 15) * 15;
    return ReminderSettings(hour: m ~/ 60, minute: m % 60, days: days);
  }
}

/// Uma notificação a agendar.
class ScheduledNote {
  final int id;
  final DateTime at; // local
  final String title;
  final String text;
  const ScheduledNote(this.id, this.at, this.title, this.text);

  Map<String, Object?> toJson() => {'id': id, 'at': at.millisecondsSinceEpoch, 'title': title, 'text': text};
}

/// Frases curtas para os lembretes (o Guará chamando para correr).
const reminderLines = <String>[
  'Bora correr hoje?',
  'Seu tênis está te esperando.',
  'Uns quilômetros hoje? O Guará já está aquecendo.',
  'Hoje é dia de correr!',
  'Só 20 minutinhos já valem.',
  'Que tal sair para correr agora?',
  'Corpo em movimento, cabeça leve. Bora?',
];

/// Monta as notificações dos próximos 14 dias a partir das preferências e do histórico.
/// É refeito ao abrir o app e após cada corrida, então os textos estão sempre atualizados.
List<ScheduledNote> planReminders({
  required List<Activity> activities,
  required ReminderSettings s,
  required double weeklyGoalKm,
  required DateTime now,
  ActivePlan? plan,
}) {
  final out = <ScheduledNote>[];
  final today = DateTime(now.year, now.month, now.day);
  final last = activities.isEmpty ? null : activities.map((a) => a.start.toLocal()).reduce((a, b) => a.isAfter(b) ? a : b);
  bool ranOn(DateTime day) => activities.any((a) {
        final l = a.start.toLocal();
        return l.year == day.year && l.month == day.month && l.day == day.day;
      });
  final nextSession = (plan == null || plan.finished) ? null : plan.plan?.sessions[plan.nextIndex!];

  if (s.reminder && s.days.isNotEmpty) {
    var k = 0;
    for (var i = 0; i < 14; i++) {
      final day = DateTime(today.year, today.month, today.day + i);
      if (!s.days.contains(day.weekday)) continue;
      final at = DateTime(day.year, day.month, day.day, s.hour, s.minute);
      if (!at.isAfter(now)) continue;
      if (i == 0 && ranOn(day)) continue;
      final idle = last == null ? null : DateTime(day.year, day.month, day.day).difference(DateTime(last.year, last.month, last.day)).inDays;
      String title, text;
      if (nextSession != null) {
        title = 'Treino do plano';
        text = '${nextSession.title}. ${nextSession.detail}';
      } else if (idle != null && idle >= 4) {
        title = 'Hora de correr';
        text = 'Já são $idle dias sem correr. Bora voltar?';
      } else {
        title = 'Hora de correr';
        text = reminderLines[(day.day + day.month) % reminderLines.length];
      }
      out.add(ScheduledNote(100 + k++, at, title, text));
    }
  }

  final weekStart = Periods.weekStart(now);
  final weekEnd = DateTime(weekStart.year, weekStart.month, weekStart.day + 7);
  final week = PeriodStats.of(Periods.between(activities, weekStart, weekEnd));
  final km = week.distanceM / 1000;

  if (s.goalNudge && weeklyGoalKm > 0) {
    final left = weeklyGoalKm - km;
    if (left > 0 && left <= weeklyGoalKm * 0.5) {
      var k = 0;
      for (final at in [
        DateTime(weekStart.year, weekStart.month, weekStart.day + 4, 18), // sexta 18h
        DateTime(weekStart.year, weekStart.month, weekStart.day + 6, 9), // domingo 9h
      ]) {
        if (!at.isAfter(now)) continue;
        out.add(ScheduledNote(200 + k++, at, 'Meta da semana quase lá',
            'Faltam ${_km(left)} km para bater ${_km(weeklyGoalKm)} km. Dá tempo!'));
      }
    }
  }

  if (s.weeklySummary) {
    final at = DateTime(weekStart.year, weekStart.month, weekStart.day + 6, 20);
    if (at.isAfter(now)) {
      final String text;
      if (week.count == 0) {
        text = 'Semana sem corridas. Semana que vem a gente volta com tudo!';
      } else {
        final pace = week.avgPace;
        final p = pace == null ? '' : ' · pace ${pace ~/ 60}:${(pace % 60).round().toString().padLeft(2, '0')}/km';
        final goal = weeklyGoalKm <= 0
            ? ''
            : km >= weeklyGoalKm
                ? ' Meta batida!'
                : ' Meta: ${(km / weeklyGoalKm * 100).round()}%.';
        text = '${week.count} ${week.count == 1 ? 'corrida' : 'corridas'} · ${_km(km)} km$p.$goal';
      }
      out.add(ScheduledNote(300, at, 'Resumo da semana', text));
    }
  }
  out.sort((a, b) => a.at.compareTo(b.at));
  return out;
}

String _km(double v) => v.toStringAsFixed(1).replaceAll('.', ',');
