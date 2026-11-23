import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../domain/achievements.dart';
import '../../domain/records.dart';

IconData badgeIcon(String name) => switch (name) {
      'flag' => Icons.flag_rounded,
      'repeat' => Icons.repeat_rounded,
      'route' => Icons.route_rounded,
      'military_tech' => Icons.military_tech_rounded,
      'emoji_events' => Icons.emoji_events_rounded,
      'timer' => Icons.timer_rounded,
      'terrain' => Icons.terrain_rounded,
      'straighten' => Icons.straighten_rounded,
      'public' => Icons.public_rounded,
      'date_range' => Icons.date_range_rounded,
      'calendar_month' => Icons.calendar_month_rounded,
      'local_fire_department' => Icons.local_fire_department_rounded,
      'whatshot' => Icons.whatshot_rounded,
      'check_circle' => Icons.check_circle_rounded,
      'verified' => Icons.verified_rounded,
      'wb_twilight' => Icons.wb_twilight_rounded,
      'nights_stay' => Icons.nights_stay_rounded,
      'bolt' => Icons.bolt_rounded,
      'speed' => Icons.speed_rounded,
      'trending_up' => Icons.trending_up_rounded,
      _ => Icons.star_rounded,
    };

/// Medalha redonda: colorida quando conquistada; cinza com anel de progresso quando não.
class BadgeMedal extends StatelessWidget {
  final Achievement badge;
  final double size;
  const BadgeMedal({super.key, required this.badge, this.size = 64});

  @override
  Widget build(BuildContext context) {
    final c = Color(badge.color);
    final on = badge.unlocked;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _MedalRing(on ? 1 : badge.progress, on ? c : const Color(0xFF94A3B8)),
        child: Padding(
          padding: EdgeInsets.all(size * 0.1),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: on
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color.lerp(c, Colors.white, 0.25)!, c, Color.lerp(c, Colors.black, 0.2)!],
                    )
                  : const LinearGradient(colors: [Color(0xFF3A4150), Color(0xFF262C36)]),
              boxShadow: on ? [BoxShadow(color: c.withValues(alpha: 0.45), blurRadius: size * 0.2)] : null,
              border: Border.all(color: Colors.white.withValues(alpha: on ? 0.55 : 0.12), width: 1.4),
            ),
            child: Center(
              child: Icon(
                on ? badgeIcon(badge.icon) : Icons.lock_rounded,
                size: size * (on ? 0.42 : 0.32),
                color: on ? Colors.white : Colors.white.withValues(alpha: 0.45),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MedalRing extends CustomPainter {
  final double p;
  final Color c;
  _MedalRing(this.p, this.c);

  @override
  void paint(Canvas canvas, Size s) {
    final r = Rect.fromCircle(center: s.center(Offset.zero), radius: s.width / 2 - 2);
    canvas.drawArc(r, 0, math.pi * 2, false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = Colors.white.withValues(alpha: 0.12));
    if (p <= 0) return;
    canvas.drawArc(r, -math.pi / 2, math.pi * 2 * p.clamp(0.0, 1.0), false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color = c);
  }

  @override
  bool shouldRepaint(_MedalRing o) => o.p != p || o.c != c;
}

/// Texto do valor de um recorde ("27:31", "21,10 km", "6:12 /km", "142 m").
String recordValue(PersonalRecord r) => switch (r.kind) {
      RecordKind.effort || RecordKind.longestTime => Fmt.duration(r.value),
      RecordKind.longestRun || RecordKind.biggestWeek || RecordKind.biggestMonth => Fmt.kmUnit(r.value),
      RecordKind.fastestFiveKPlusRun => Fmt.paceUnit(r.value),
      RecordKind.mostClimb => '${Fmt.integer(r.value)} m',
    };

/// Pace equivalente de um esforço ("5:30 /km").
String? recordPace(PersonalRecord r) =>
    r.kind == RecordKind.effort && r.meters != null ? Fmt.paceUnit(r.value / (r.meters! / 1000)) : null;

String recordWhen(PersonalRecord r) => switch (r.kind) {
      RecordKind.biggestWeek => 'Semana de ${Fmt.dayMonth(r.date.toLocal())}/${r.date.toLocal().year}',
      RecordKind.biggestMonth => Fmt.monthYear(r.date.toLocal()),
      _ => Fmt.date(r.date),
    };

IconData recordIcon(PersonalRecord r) => switch (r.kind) {
      RecordKind.effort => Icons.timer_rounded,
      RecordKind.longestRun => Icons.route_rounded,
      RecordKind.longestTime => Icons.hourglass_bottom_rounded,
      RecordKind.biggestWeek => Icons.date_range_rounded,
      RecordKind.biggestMonth => Icons.calendar_month_rounded,
      RecordKind.mostClimb => Icons.terrain_rounded,
      RecordKind.fastestFiveKPlusRun => Icons.bolt_rounded,
    };
