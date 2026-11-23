import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/format.dart';
import '../../domain/achievements.dart';
import '../../domain/records.dart';
import 'guara_art.dart';

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

/// Desenho no centro da medalha: número gravado, um símbolo ou o Guará (platina).
class MedalFace {
  final String? big;
  final String? small;
  final String? top;
  final MedalSymbol? symbol;
  final bool guara;
  const MedalFace({this.big, this.small, this.top, this.symbol, this.guara = false});

  static MedalFace of(Achievement a) => switch (a.id) {
        'first_run' => const MedalFace(symbol: MedalSymbol.shoe),
        'runs_10' => const MedalFace(big: '10', small: 'CORRIDAS'),
        'runs_50' => const MedalFace(big: '50', small: 'CORRIDAS'),
        'runs_100' => const MedalFace(big: '100', small: 'CORRIDAS'),
        'runs_250' => const MedalFace(guara: true, small: '250 CORRIDAS'),
        'dist_5k' => const MedalFace(big: '5', small: 'KM'),
        'dist_10k' => const MedalFace(big: '10', small: 'KM'),
        'dist_15k' => const MedalFace(big: '15', small: 'KM'),
        'dist_21k' => const MedalFace(big: '21', small: 'KM'),
        'dist_42k' => const MedalFace(guara: true, small: '42 KM'),
        'hour_run' => const MedalFace(symbol: MedalSymbol.stopwatch, small: '1 HORA'),
        'climb_100' => const MedalFace(symbol: MedalSymbol.mountain, small: '100 M'),
        'total_50' => const MedalFace(big: '50', small: 'KM'),
        'total_100' => const MedalFace(big: '100', small: 'KM'),
        'total_250' => const MedalFace(big: '250', small: 'KM'),
        'total_500' => const MedalFace(big: '500', small: 'KM'),
        'total_1000' => const MedalFace(big: '1.000', small: 'KM'),
        'total_2500' => const MedalFace(guara: true, small: '2.500 KM'),
        'week_30' => const MedalFace(big: '30', small: 'KM/SEMANA'),
        'month_100' => const MedalFace(big: '100', small: 'KM/MÊS'),
        'streak_4' => const MedalFace(symbol: MedalSymbol.flame, big: '4', small: 'SEMANAS'),
        'streak_8' => const MedalFace(symbol: MedalSymbol.flame, big: '8', small: 'SEMANAS'),
        'streak_12' => const MedalFace(symbol: MedalSymbol.flame, big: '12', small: 'SEMANAS'),
        'streak_26' => const MedalFace(guara: true, small: '26 SEMANAS'),
        'goal_week_1' => const MedalFace(symbol: MedalSymbol.target),
        'goal_week_10' => const MedalFace(symbol: MedalSymbol.target, small: '10 VEZES'),
        'early_bird' => const MedalFace(symbol: MedalSymbol.sunrise),
        'early_bird_10' => const MedalFace(symbol: MedalSymbol.clock5),
        'night_owl' => const MedalFace(symbol: MedalSymbol.owl),
        'night_owl_10' => const MedalFace(symbol: MedalSymbol.moon),
        'sub30_5k' => const MedalFace(top: 'SUB', big: '30', small: '5 KM'),
        'sub25_5k' => const MedalFace(top: 'SUB', big: '25', small: '5 KM'),
        'sub60_10k' => const MedalFace(top: 'SUB', big: '60', small: '10 KM'),
        'sub50_10k' => const MedalFace(top: 'SUB', big: '50', small: '10 KM'),
        'pace_6' => const MedalFace(symbol: MedalSymbol.gauge, small: '6:00/KM'),
        'pace_5' => const MedalFace(symbol: MedalSymbol.gauge, small: '5:00/KM'),
        _ => const MedalFace(symbol: MedalSymbol.shoe),
      };
}

enum MedalSymbol { shoe, stopwatch, mountain, flame, target, sunrise, clock5, owl, moon, gauge }

/// Metais: claro, médio, escuro, sombra, cor da gravação.
const _metals = <List<Color>>[
  [Color(0xFFF6D2B0), Color(0xFFD08B55), Color(0xFFA7602E), Color(0xFF6B3815), Color(0xFF5A2E10)], // bronze
  [Color(0xFFFFFFFF), Color(0xFFD9E0E8), Color(0xFF9AA6B4), Color(0xFF5D6876), Color(0xFF465260)], // prata
  [Color(0xFFFFF6C4), Color(0xFFFFD54A), Color(0xFFE0A100), Color(0xFF8A5A00), Color(0xFF6E4600)], // ouro
  [Color(0xFFF4FBFF), Color(0xFFCFE6FF), Color(0xFF8DB4E8), Color(0xFF3F6AA6), Color(0xFF2B4C7E)], // platina
];
const _lockedMetal = [Color(0xFF4B5363), Color(0xFF363D4A), Color(0xFF2A303B), Color(0xFF1C2129), Color(0xFF7D8898)];

/// Cor da fita por grupo.
Color ribbonColor(BadgeGroup g) => switch (g) {
      BadgeGroup.firsts => const Color(0xFF14B887),
      BadgeGroup.distance => const Color(0xFF0EA5E9),
      BadgeGroup.volume => const Color(0xFF7C5CF0),
      BadgeGroup.habit => const Color(0xFFF97316),
      BadgeGroup.speed => const Color(0xFFE11D48),
    };

/// Medalha de metal com fita: bronze, prata, ouro ou platina; bloqueada fica escura com o progresso.
/// [size] é a largura; a altura é 1,45 × a largura (a fita fica em cima).
class BadgeMedal extends StatefulWidget {
  final Achievement badge;
  final double size;

  /// Reflexo passando pelo metal de tempos em tempos.
  final bool shine;
  const BadgeMedal({super.key, required this.badge, this.size = 72, this.shine = false});

  @override
  State<BadgeMedal> createState() => _BadgeMedalState();
}

class _BadgeMedalState extends State<BadgeMedal> with SingleTickerProviderStateMixin {
  AnimationController? _c;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final want = widget.shine && widget.badge.unlocked && MediaQuery.maybeDisableAnimationsOf(context) != true;
    if (want && _c == null) {
      _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 3600))..repeat();
    } else if (!want && _c != null) {
      _c!.dispose();
      _c = null;
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.badge;
    final w = widget.size;
    final h = w * 1.45;
    final face = MedalFace.of(b);
    final r = w * 0.4;
    final cy = h - w / 2 - w * 0.04;
    final paint = CustomPaint(
      size: Size(w, h),
      painter: _MedalPainter(b, face, _c),
    );
    return Semantics(
      label: '${b.title}${b.unlocked ? ', conquistada' : ', bloqueada'}',
      child: SizedBox(
        width: w,
        height: h,
        child: Stack(
          children: [
            paint,
            if (b.unlocked && face.guara)
              Positioned(
                left: w / 2 - r * 0.52,
                top: cy - r * 0.74,
                width: r * 1.04,
                height: r * 1.04,
                child: SvgPicture.string(GuaraArt.head, fit: BoxFit.contain),
              ),
          ],
        ),
      ),
    );
  }
}

class _MedalPainter extends CustomPainter {
  final Achievement b;
  final MedalFace face;
  final Animation<double>? shine;
  _MedalPainter(this.b, this.face, this.shine) : super(repaint: shine);

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final on = b.unlocked;
    final m = on ? _metals[b.tier.clamp(0, 3)] : _lockedMetal;
    final cx = w / 2, cy = h - w / 2 - w * 0.04, r = w * 0.4;
    final c = Offset(cx, cy);
    final rib = ribbonColor(b.group);
    final ribMain = on ? rib : Color.lerp(rib, const Color(0xFF2C323D), 0.78)!;
    final ribDark = Color.lerp(ribMain, Colors.black, 0.3)!;
    final stripe = on ? Colors.white : Colors.white.withValues(alpha: 0.18);

    // Fita: duas tiras que se cruzam na argola.
    final top = cy - r - w * 0.13;
    final rw = w * 0.16;
    for (final side in [-1, 1]) {
      final x0 = cx + side * w * 0.36;
      final x1 = x0 - side * rw;
      final path = Path()
        ..moveTo(x0, 0)
        ..lineTo(x1, 0)
        ..lineTo(cx + side * -3, top)
        ..lineTo(cx + side * 6, top + 2)
        ..close();
      final bounds = path.getBounds();
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            colors: [ribDark, ribMain, ribMain, stripe, stripe, ribMain, ribMain, stripe, stripe, ribMain, ribDark],
            stops: const [0, 0.12, 0.25, 0.25, 0.34, 0.34, 0.66, 0.66, 0.75, 0.75, 1],
            transform: GradientRotation(side * -0.42),
          ).createShader(bounds),
      );
      if (side == 1) canvas.drawPath(path, Paint()..color = Colors.black.withValues(alpha: 0.12));
    }

    final metal = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [m[0], m[1], m[2], m[3]],
      stops: const [0, 0.35, 0.7, 1],
    );
    // Presilha e argola.
    final clasp = Rect.fromLTWH(cx - w * 0.09, top - 3, w * 0.18, w * 0.085);
    canvas.drawRRect(RRect.fromRectAndRadius(clasp, const Radius.circular(3)), Paint()..shader = metal.createShader(clasp));
    canvas.drawRRect(
        RRect.fromRectAndRadius(clasp, const Radius.circular(3)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = m[4].withValues(alpha: 0.7));
    final ringC = Offset(cx, cy - r - 2);
    canvas.drawCircle(
        ringC,
        w * 0.06,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.03
          ..shader = metal.createShader(Rect.fromCircle(center: ringC, radius: w * 0.08)));

    // Sombra, aro serrilhado, aro interno invertido e centro polido.
    if (on) canvas.drawCircle(c.translate(0, 3), r + 2, Paint()..color = Colors.black.withValues(alpha: 0.35));
    final disc = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(c, r, Paint()..shader = metal.createShader(disc));
    final tick = Paint()
      ..color = m[4].withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (var i = 0; i < 60; i++) {
      final a = i / 60 * math.pi * 2;
      final d = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + d * (r - 0.5), c + d * (r - w * 0.035), tick);
    }
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(math.pi);
    canvas.drawCircle(Offset.zero, r * 0.8, Paint()..shader = metal.createShader(Rect.fromCircle(center: Offset.zero, radius: r * 0.8)));
    canvas.restore();
    canvas.drawCircle(
      c,
      r * 0.74,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.4),
          radius: 0.95,
          colors: [m[0], m[1], m[2]],
          stops: const [0, 0.45, 1],
        ).createShader(Rect.fromCircle(center: c, radius: r * 0.74)),
    );
    canvas.drawCircle(
        c,
        r * 0.66,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = m[4].withValues(alpha: 0.4));

    // Louros no ouro e na platina.
    if (on && b.tier >= 2) {
      final leaf = Paint()..color = m[4].withValues(alpha: 0.5);
      for (final side in [-1, 1]) {
        for (var i = 0; i < 5; i++) {
          final a = math.pi / 2 + side * (0.95 + i * 0.26);
          final p = c + Offset(math.cos(a), math.sin(a)) * r * 0.62;
          canvas.save();
          canvas.translate(p.dx, p.dy);
          canvas.rotate(a + side * math.pi / 3);
          canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: w * 0.06, height: w * 0.028), leaf);
          canvas.restore();
        }
      }
    }

    // Centro.
    if (!on) {
      _lock(canvas, c, w, m[4]);
    } else if (!face.guara) {
      _emboss(canvas, (cv, color, light) => _face(cv, c, w, r, color, light), m[4]);
    }
    if (on && face.guara && face.small != null) {
      _text(canvas, face.small!, c.translate(0, r * 0.56), w * 0.06, m[4], spacing: 0.6, weight: FontWeight.w700);
    }

    // Brilhos: reflexo fixo e reflexo que passa.
    if (on) {
      canvas.save();
      canvas.translate(cx - r * 0.35, cy - r * 0.45);
      canvas.rotate(-0.5);
      canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: r * 0.62, height: r * 0.26),
          Paint()..color = Colors.white.withValues(alpha: 0.28));
      canvas.restore();
      final t = shine?.value;
      if (t != null && t < 0.55) {
        canvas.save();
        canvas.clipPath(Path()..addOval(disc));
        final x = cx - r * 1.6 + (t / 0.55) * r * 3.2;
        canvas.translate(x, cy);
        canvas.rotate(0.45);
        canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: w * 0.12, height: r * 4),
            Paint()..color = Colors.white.withValues(alpha: 0.42));
        canvas.restore();
      }
    } else {
      // Anel de progresso em volta da bloqueada.
      final rr = r + w * 0.05;
      final rect = Rect.fromCircle(center: c, radius: rr);
      canvas.drawCircle(
          c,
          rr,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = w * 0.035
            ..color = Colors.white.withValues(alpha: 0.08));
      if (b.progress > 0) {
        canvas.drawArc(
            rect,
            -math.pi / 2,
            math.pi * 2 * b.progress.clamp(0.0, 1.0),
            false,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = w * 0.035
              ..strokeCap = StrokeCap.round
              ..color = rib);
      }
    }
  }

  /// Desenha duas vezes (luz embaixo-direita, gravação em cima) para parecer cunhado.
  void _emboss(Canvas canvas, void Function(Canvas, Color, bool) draw, Color engraved) {
    canvas.save();
    canvas.translate(0.9, 1.1);
    draw(canvas, Colors.white.withValues(alpha: 0.55), true);
    canvas.restore();
    canvas.save();
    canvas.translate(-0.5, -0.5);
    draw(canvas, engraved, false);
    canvas.restore();
  }

  /// [light]: passada de luz do relevo (letras pequenas só na passada final, para não borrar).
  void _face(Canvas canvas, Offset c, double w, double r, Color color, bool light) {
    final f = face;
    if (f.symbol != null) {
      final hasNum = f.symbol == MedalSymbol.flame && f.big != null;
      final box = r * (f.small != null && !hasNum ? 0.82 : 0.95);
      final origin = c.translate(-box / 2, -box / 2 - (f.small != null && !hasNum ? r * 0.12 : 0));
      _symbol(canvas, f.symbol!, origin, box / 24, color);
      if (hasNum) {
        _text(canvas, f.big!, origin + Offset(box / 2, box * 0.62), w * 0.13, Color.lerp(color, Colors.white, 0.0)!,
            weight: FontWeight.w700, knock: true);
      }
      if (f.small != null && !light) {
        _text(canvas, f.small!, c.translate(0, r * 0.52), w * 0.062, color, spacing: 0.6, weight: FontWeight.w700);
      }
      return;
    }
    final big = f.big ?? '';
    final size = switch (big.length) { 1 => w * 0.3, 2 => w * 0.25, 3 => w * 0.2, _ => w * 0.15 };
    final dy = f.top != null ? r * 0.08 : -r * 0.06;
    _text(canvas, big, c.translate(0, dy), size, color, weight: FontWeight.w700);
    if (light) return;
    if (f.top != null) _text(canvas, f.top!, c.translate(0, dy - size * 0.66), w * 0.065, color, spacing: 1.4, weight: FontWeight.w700);
    if (f.small != null) {
      _text(canvas, f.small!, c.translate(0, dy + size * 0.66), f.small!.length > 6 ? w * 0.052 : w * 0.07, color,
          spacing: 0.6, weight: FontWeight.w700);
    }
  }

  void _text(Canvas canvas, String s, Offset center, double size, Color color,
      {double spacing = 0, FontWeight weight = FontWeight.w500, bool knock = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          fontFamily: 'SpaceGrotesk',
          fontSize: size,
          fontWeight: weight,
          letterSpacing: spacing,
          height: 1,
          color: knock ? _metalsLight : color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  Color get _metalsLight => _metals[b.tier.clamp(0, 3)][1];

  void _lock(Canvas canvas, Offset c, double w, Color color) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.035;
    final u = w * 0.012;
    canvas.drawArc(Rect.fromCenter(center: c.translate(0, -u * 3), width: u * 12, height: u * 12), math.pi, math.pi, false, p);
    canvas.drawLine(c.translate(-u * 6, -u * 3), c.translate(-u * 6, 0), p);
    canvas.drawLine(c.translate(u * 6, -u * 3), c.translate(u * 6, 0), p);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: c.translate(0, u * 4.5), width: u * 17, height: u * 12), Radius.circular(u * 2.5)),
        Paint()..color = color);
  }

  /// Símbolos desenhados numa grade de 24 × 24.
  void _symbol(Canvas canvas, MedalSymbol s, Offset o, double k, Color color) {
    canvas.save();
    canvas.translate(o.dx, o.dy);
    canvas.scale(k);
    final fill = Paint()..color = color;
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.9
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final thin = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    switch (s) {
      case MedalSymbol.shoe:
        // Tênis de corrida de lado, com cadarços e solado.
        canvas.drawPath(
            Path()
              ..moveTo(2.5, 15.5)
              ..cubicTo(2.5, 13.2, 3.8, 12.2, 5.6, 12.0)
              ..lineTo(8.4, 7.6)
              ..lineTo(11.2, 8.8)
              ..lineTo(10.6, 10.6)
              ..cubicTo(12.8, 11.6, 15.6, 11.9, 17.8, 12.7)
              ..cubicTo(20.4, 13.6, 21.6, 14.6, 21.6, 16.0)
              ..lineTo(21.6, 16.6)
              ..lineTo(2.5, 16.6)
              ..close(),
            fill);
        canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(2.2, 17.4, 19.8, 1.9), const Radius.circular(1)), fill);
        final lace = Paint()
          ..color = _metalsLight
          ..strokeWidth = 0.9
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(const Offset(11.4, 11.4), const Offset(12.6, 9.9), lace);
        canvas.drawLine(const Offset(13.1, 11.9), const Offset(14.3, 10.4), lace);
        canvas.drawLine(const Offset(14.8, 12.3), const Offset(16.0, 10.8), lace);
        canvas.drawLine(const Offset(3.6, 15.3), const Offset(8.0, 15.3), lace..strokeWidth = 0.7);
      case MedalSymbol.stopwatch:
        canvas.drawCircle(const Offset(12, 13.5), 7.5, line);
        canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(10.3, 2.6, 3.4, 2.4), const Radius.circular(0.8)), fill);
        canvas.drawLine(const Offset(12, 5.0), const Offset(12, 6.0), line);
        canvas.drawLine(const Offset(18.2, 6.6), const Offset(19.4, 5.4), line);
        canvas.drawLine(const Offset(12, 13.5), const Offset(12, 9.0), line);
        canvas.drawLine(const Offset(12, 13.5), const Offset(15.2, 15.2), line);
        canvas.drawCircle(const Offset(12, 13.5), 1.1, fill);
        for (var i = 0; i < 12; i++) {
          final a = i / 12 * math.pi * 2;
          canvas.drawCircle(Offset(12 + math.cos(a) * 5.7, 13.5 + math.sin(a) * 5.7), 0.35, fill);
        }
      case MedalSymbol.mountain:
        canvas.drawPath(
            Path()
              ..moveTo(1.5, 20)
              ..lineTo(9, 8.5)
              ..lineTo(12.4, 13.4)
              ..lineTo(15.2, 10.2)
              ..lineTo(22.5, 20)
              ..close(),
            fill);
        canvas.drawPath(
            Path()
              ..moveTo(7.0, 11.6)
              ..lineTo(9, 8.5)
              ..lineTo(11.0, 11.4)
              ..lineTo(10.0, 10.8)
              ..lineTo(9.0, 11.8)
              ..lineTo(8.0, 10.9)
              ..close(),
            Paint()..color = _metalsLight);
        canvas.drawLine(const Offset(9, 8.5), const Offset(9, 2.6), thin..strokeWidth = 1.1);
        canvas.drawPath(
            Path()
              ..moveTo(9.2, 2.6)
              ..lineTo(14.0, 3.9)
              ..lineTo(9.2, 5.3)
              ..close(),
            fill);
      case MedalSymbol.flame:
        canvas.drawPath(
            Path()
              ..moveTo(12, 1.5)
              ..cubicTo(13.4, 5.6, 19, 8.2, 19, 14.6)
              ..cubicTo(19, 18.8, 15.8, 22, 12, 22)
              ..cubicTo(8.2, 22, 5, 18.8, 5, 14.6)
              ..cubicTo(5, 11.4, 6.8, 9.6, 8.6, 8.4)
              ..cubicTo(8.4, 10.6, 9.4, 12, 10.8, 12.2)
              ..cubicTo(10.4, 8.2, 10.2, 5.2, 12, 1.5)
              ..close(),
            fill);
      case MedalSymbol.target:
        canvas.drawCircle(const Offset(11, 13), 8.2, line);
        canvas.drawCircle(const Offset(11, 13), 5.0, line);
        canvas.drawCircle(const Offset(11, 13), 1.8, fill);
        canvas.drawLine(const Offset(11, 13), const Offset(19.5, 4.5), line);
        canvas.drawPath(
            Path()
              ..moveTo(19.5, 4.5)
              ..lineTo(19.8, 1.8)
              ..lineTo(21.4, 3.2)
              ..lineTo(22.2, 2.6)
              ..lineTo(21.6, 5.0)
              ..close(),
            fill);
        canvas.drawLine(const Offset(19.5, 4.5), const Offset(22.2, 4.8), thin);
      case MedalSymbol.sunrise:
        canvas.drawArc(Rect.fromCircle(center: const Offset(12, 16), radius: 5.2), math.pi, math.pi, true, fill);
        for (final a in [-90.0, -125.0, -55.0, -160.0, -20.0]) {
          final r = a * math.pi / 180;
          canvas.drawLine(Offset(12 + math.cos(r) * 7.2, 16 + math.sin(r) * 7.2), Offset(12 + math.cos(r) * 9.6, 16 + math.sin(r) * 9.6), line);
        }
        canvas.drawLine(const Offset(2, 16.4), const Offset(22, 16.4), line);
        canvas.drawLine(const Offset(5, 19.6), const Offset(19, 19.6), thin);
      case MedalSymbol.clock5:
        canvas.drawCircle(const Offset(12, 12), 8.6, line);
        for (var i = 0; i < 12; i++) {
          final a = i / 12 * math.pi * 2;
          final d = Offset(math.cos(a), math.sin(a));
          canvas.drawLine(const Offset(12, 12) + d * 6.6, const Offset(12, 12) + d * (i % 3 == 0 ? 7.8 : 7.3), thin..strokeWidth = 0.9);
        }
        canvas.drawLine(const Offset(12, 12), const Offset(12, 6.2), line);
        final h5 = (5 / 12) * math.pi * 2 - math.pi / 2;
        canvas.drawLine(const Offset(12, 12), Offset(12 + math.cos(h5) * 4.2, 12 + math.sin(h5) * 4.2), line..strokeWidth = 2.3);
        canvas.drawCircle(const Offset(12, 12), 1, fill);
      case MedalSymbol.owl:
        canvas.drawPath(
            Path()
              ..moveTo(5, 5)
              ..lineTo(8, 7.5)
              ..lineTo(16, 7.5)
              ..lineTo(19, 5)
              ..lineTo(19, 15)
              ..cubicTo(19, 19.5, 15.8, 22, 12, 22)
              ..cubicTo(8.2, 22, 5, 19.5, 5, 15)
              ..close(),
            fill);
        final hole = Paint()..color = _metalsLight;
        canvas.drawCircle(const Offset(9.2, 12), 2.6, hole);
        canvas.drawCircle(const Offset(14.8, 12), 2.6, hole);
        canvas.drawCircle(const Offset(9.6, 12.2), 1.2, fill);
        canvas.drawCircle(const Offset(14.4, 12.2), 1.2, fill);
        canvas.drawPath(
            Path()
              ..moveTo(11, 14.6)
              ..lineTo(13, 14.6)
              ..lineTo(12, 16.4)
              ..close(),
            hole);
        for (final x in [9.0, 12.0, 15.0]) {
          canvas.drawArc(Rect.fromCenter(center: Offset(x, 18.6), width: 2.6, height: 2.0), 0, math.pi, false,
              Paint()
                ..color = _metalsLight
                ..style = PaintingStyle.stroke
                ..strokeWidth = 0.8);
        }
      case MedalSymbol.moon:
        canvas.drawPath(
            Path.combine(
              PathOperation.difference,
              Path()..addOval(Rect.fromCircle(center: const Offset(11, 13), radius: 8)),
              Path()..addOval(Rect.fromCircle(center: const Offset(15.2, 10.4), radius: 7)),
            ),
            fill);
        _star(canvas, const Offset(18.4, 15.6), 2.4, fill);
        _star(canvas, const Offset(15.4, 4.2), 1.6, fill);
        canvas.drawCircle(const Offset(20.6, 8.4), 0.8, fill);
      case MedalSymbol.gauge:
        final rect = Rect.fromCircle(center: const Offset(12, 15), radius: 9);
        canvas.drawArc(rect, math.pi * 0.85, math.pi * 1.3, false, line);
        for (var i = 0; i <= 6; i++) {
          final a = math.pi * 0.85 + i / 6 * math.pi * 1.3;
          final d = Offset(math.cos(a), math.sin(a));
          canvas.drawLine(const Offset(12, 15) + d * 6.2, const Offset(12, 15) + d * 7.6, thin);
        }
        final na = math.pi * 1.85;
        canvas.drawLine(const Offset(12, 15), Offset(12 + math.cos(na) * 7.0, 15 + math.sin(na) * 7.0), line..strokeWidth = 2.2);
        canvas.drawCircle(const Offset(12, 15), 1.7, fill);
    }
    canvas.restore();
  }

  void _star(Canvas canvas, Offset c, double r, Paint p) {
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final a = i / 8 * math.pi * 2 - math.pi / 2;
      final rr = i.isEven ? r : r * 0.38;
      final pt = c + Offset(math.cos(a), math.sin(a)) * rr;
      i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
    }
    canvas.drawPath(path..close(), p);
  }

  @override
  bool shouldRepaint(_MedalPainter o) => o.b != b || o.shine != shine;
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

/// Medalha que "cai" balançando na fita, com vibração (ao desbloquear).
class MedalDrop extends StatefulWidget {
  final Widget child;
  final int delayMs;
  const MedalDrop({super.key, required this.child, this.delayMs = 0});

  @override
  State<MedalDrop> createState() => _MedalDropState();
}

class _MedalDropState extends State<MedalDrop> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300));

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: 250 + widget.delayMs), () {
      if (!mounted) return;
      if (MediaQuery.maybeDisableAnimationsOf(context) == true) {
        _c.value = 1;
        return;
      }
      HapticFeedback.mediumImpact();
      _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final v = _c.value;
        final fall = Curves.easeOutCubic.transform((v / 0.35).clamp(0.0, 1.0));
        // Balanço amortecido depois da queda.
        final swing = v < 0.35 ? -0.25 * (1 - fall) : 0.22 * math.exp(-5 * (v - 0.35)) * math.sin((v - 0.35) * 22);
        return Opacity(
          opacity: (v * 4).clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, -46 * (1 - fall)),
            child: Transform.rotate(angle: swing, alignment: Alignment.topCenter, child: child),
          ),
        );
      },
    );
  }
}
