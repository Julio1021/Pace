import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/theme.dart';
import 'pace_ui.dart';

/// Momentos do dia mostrados no céu da tela Correr.
enum SkyMoment { aurora, sunrise, day, sunset, dusk, night }

/// Nascer e pôr do sol calculados para a data e o lugar (algoritmo da NOAA).
class SunTimes {
  final DateTime sunrise;
  final DateTime sunset;
  const SunTimes(this.sunrise, this.sunset);

  factory SunTimes.of(DateTime localDay, double lat, double lon) {
    final day = DateTime.utc(localDay.year, localDay.month, localDay.day);
    final n = day.difference(DateTime.utc(day.year)).inDays + 1;
    final g = 2 * math.pi / 365 * (n - 1);
    final eq = 229.18 *
        (0.000075 + 0.001868 * math.cos(g) - 0.032077 * math.sin(g) - 0.014615 * math.cos(2 * g) - 0.040849 * math.sin(2 * g));
    final decl = 0.006918 -
        0.399912 * math.cos(g) +
        0.070257 * math.sin(g) -
        0.006758 * math.cos(2 * g) +
        0.000907 * math.sin(2 * g) -
        0.002697 * math.cos(3 * g) +
        0.00148 * math.sin(3 * g);
    final la = lat * math.pi / 180;
    final c = math.cos(90.833 * math.pi / 180) / (math.cos(la) * math.cos(decl)) - math.tan(la) * math.tan(decl);
    final ha = math.acos(c.clamp(-1.0, 1.0)) * 180 / math.pi;
    final rise = 720 - 4 * (lon + ha) - eq;
    final set = 720 - 4 * (lon - ha) - eq;
    // Converte para o fuso do aparelho mantendo o dia local pedido.
    final offset = localDay.timeZoneOffset;
    DateTime at(double minUtc) {
      final local = day.add(Duration(seconds: (minUtc * 60).round())).add(offset);
      return DateTime(local.year, local.month, local.day, local.hour, local.minute, local.second);
    }

    return SunTimes(at(rise), at(set));
  }
}

/// Cores de um instante; interpoladas entre os momentos para a troca ser suave.
class SkyLook {
  final Color top, mid, low;
  final Color hillFar, hillMid, hillNear, ground;
  final Color sun;
  final Color cloud;
  final double cloudAlpha;
  final double stars;
  const SkyLook({
    required this.top,
    required this.mid,
    required this.low,
    required this.hillFar,
    required this.hillMid,
    required this.hillNear,
    required this.ground,
    required this.sun,
    required this.cloud,
    required this.cloudAlpha,
    required this.stars,
  });

  static SkyLook lerp(SkyLook a, SkyLook b, double t) {
    Color c(Color x, Color y) => Color.lerp(x, y, t)!;
    double d(double x, double y) => x + (y - x) * t;
    return SkyLook(
      top: c(a.top, b.top),
      mid: c(a.mid, b.mid),
      low: c(a.low, b.low),
      hillFar: c(a.hillFar, b.hillFar),
      hillMid: c(a.hillMid, b.hillMid),
      hillNear: c(a.hillNear, b.hillNear),
      ground: c(a.ground, b.ground),
      sun: c(a.sun, b.sun),
      cloud: c(a.cloud, b.cloud),
      cloudAlpha: d(a.cloudAlpha, b.cloudAlpha),
      stars: d(a.stars, b.stars),
    );
  }

  static const looks = <SkyMoment, SkyLook>{
    SkyMoment.night: SkyLook(
      top: Color(0xFF0B1030), mid: Color(0xFF1A1F4E), low: Color(0xFF2E2F66),
      hillFar: Color(0xFF2A2C5C), hillMid: Color(0xFF1E2A4A), hillNear: Color(0xFF16263A), ground: Color(0xFF111B2B),
      sun: Color(0xFFFFB347), cloud: Color(0xFF8C93C9), cloudAlpha: 0.10, stars: 1,
    ),
    SkyMoment.aurora: SkyLook(
      top: Color(0xFF23285C), mid: Color(0xFF6C5496), low: Color(0xFFF2A487),
      hillFar: Color(0xFF6A5A8E), hillMid: Color(0xFF4C5C7C), hillNear: Color(0xFF3B6460), ground: Color(0xFF263943),
      sun: Color(0xFFFF9D5C), cloud: Color(0xFFE7A3B6), cloudAlpha: 0.28, stars: 0.5,
    ),
    SkyMoment.sunrise: SkyLook(
      top: Color(0xFF7BA6DD), mid: Color(0xFFF3C3A6), low: Color(0xFFFFD99C),
      hillFar: Color(0xFFC9B2CF), hillMid: Color(0xFF9CC4B6), hillNear: Color(0xFF6FC39E), ground: Color(0xFFD5EEDF),
      sun: Color(0xFFFFB24D), cloud: Color(0xFFFFE3D2), cloudAlpha: 0.65, stars: 0,
    ),
    SkyMoment.day: SkyLook(
      top: Color(0xFF5AA2F0), mid: Color(0xFFA8D0FB), low: Color(0xFFE8F3FF),
      hillFar: Color(0xFFB4D3E6), hillMid: Color(0xFF93D3BA), hillNear: Color(0xFF5FC596), ground: Color(0xFFD9F1E4),
      sun: Color(0xFFFFD56B), cloud: Color(0xFFFFFFFF), cloudAlpha: 0.9, stars: 0,
    ),
    SkyMoment.sunset: SkyLook(
      top: Color(0xFF8C7DD0), mid: Color(0xFFF5A28A), low: Color(0xFFFFD3A0),
      hillFar: Color(0xFFC8A2C4), hillMid: Color(0xFFA9AFA9), hillNear: Color(0xFF7FB494), ground: Color(0xFFEBDCCF),
      sun: Color(0xFFFF8A48), cloud: Color(0xFFFFCDBE), cloudAlpha: 0.75, stars: 0,
    ),
    SkyMoment.dusk: SkyLook(
      top: Color(0xFF1D2152), mid: Color(0xFF583E86), low: Color(0xFFC9758E),
      hillFar: Color(0xFF4B3C70), hillMid: Color(0xFF384867), hillNear: Color(0xFF2C5150), ground: Color(0xFF1C2837),
      sun: Color(0xFFFF7A45), cloud: Color(0xFFB88AB8), cloudAlpha: 0.3, stars: 0.55,
    ),
  };
}

/// Tudo o que a tela precisa saber sobre o céu agora.
class SkyInfo {
  final DateTime now;
  final SunTimes sun;
  final SkyMoment moment;
  final SkyLook look;
  const SkyInfo(this.now, this.sun, this.moment, this.look);

  /// Lugar padrão quando ainda não há corrida com GPS (Vale do Paraíba).
  static const defaultLat = -22.81;
  static const defaultLon = -45.19;

  factory SkyInfo.at(DateTime now, {double lat = defaultLat, double lon = defaultLon}) {
    final s = SunTimes.of(now, lat, lon);
    final sr = s.sunrise, ss = s.sunset;
    DateTime m(DateTime b, int min) => b.add(Duration(minutes: min));
    // Quadros-chave: entre eles as cores se misturam.
    final keys = <(DateTime, SkyMoment)>[
      (m(sr, -95), SkyMoment.night),
      (m(sr, -35), SkyMoment.aurora),
      (m(sr, 15), SkyMoment.sunrise),
      (m(sr, 100), SkyMoment.day),
      (m(ss, -110), SkyMoment.day),
      (m(ss, -25), SkyMoment.sunset),
      (m(ss, 20), SkyMoment.dusk),
      (m(ss, 70), SkyMoment.night),
    ];
    var look = SkyLook.looks[SkyMoment.night]!;
    for (var i = 0; i < keys.length - 1; i++) {
      final a = keys[i], b = keys[i + 1];
      if (!now.isBefore(a.$1) && now.isBefore(b.$1)) {
        final t = now.difference(a.$1).inSeconds / b.$1.difference(a.$1).inSeconds;
        final e = t * t * (3 - 2 * t);
        look = SkyLook.lerp(SkyLook.looks[a.$2]!, SkyLook.looks[b.$2]!, e);
      }
    }
    SkyMoment moment;
    if (now.isBefore(m(sr, -60))) {
      moment = SkyMoment.night;
    } else if (now.isBefore(m(sr, -2))) {
      moment = SkyMoment.aurora;
    } else if (now.isBefore(m(sr, 75))) {
      moment = SkyMoment.sunrise;
    } else if (now.isBefore(m(ss, -90))) {
      moment = SkyMoment.day;
    } else if (now.isBefore(m(ss, 3))) {
      moment = SkyMoment.sunset;
    } else if (now.isBefore(m(ss, 45))) {
      moment = SkyMoment.dusk;
    } else {
      moment = SkyMoment.night;
    }
    return SkyInfo(now, s, moment, look);
  }

  String get label => switch (moment) {
        SkyMoment.aurora => 'amanhecer',
        SkyMoment.sunrise => 'nascer do sol',
        SkyMoment.day => now.hour < 12 ? 'manhã' : 'tarde',
        SkyMoment.sunset => 'pôr do sol',
        SkyMoment.dusk => 'anoitecer',
        SkyMoment.night => now.hour < 5 ? 'madrugada' : 'noite',
      };

  String get phrase {
    final list = switch (moment) {
      SkyMoment.aurora => ['Ar fresquinho lá fora. Bora?', 'Ainda está escuro: vá de roupa clara.'],
      SkyMoment.sunrise => ['O dia está nascendo. Bora?', 'Começar o dia correndo é outro nível.'],
      SkyMoment.day => now.hour >= 10 && now.hour < 16
          ? ['Sol forte: leve água e se hidrate.', 'Bom momento para sair']
          : ['Bom momento para sair', 'Que tal uns quilômetros agora?'],
      SkyMoment.sunset => ['Fim de tarde perfeito para correr', 'Corra com o pôr do sol.'],
      SkyMoment.dusk => ['A luz está indo. Use algo refletivo.', 'Anoitecendo: seja visto, use refletivo.'],
      SkyMoment.night => ['Corrida noturna? Use roupa refletiva.', 'Noite tranquila para uns quilômetros.'],
    };
    return list[now.day % list.length];
  }

  static bool _isDark(Color c) => c.computeLuminance() < 0.32;

  /// Texto sobre o céu (título e frase).
  Color get onSky => _isDark(Color.lerp(look.top, look.mid, 0.5)!) ? Colors.white : PaceColors.ink;

  /// Texto sobre o chão (títulos das seções).
  Color get onGround => _isDark(look.ground) ? Colors.white : PaceColors.ink;

  /// Fração iluminada da lua (0 nova, 1 cheia) e se está crescendo.
  ({double lit, bool waxing}) get moon {
    const synodic = 29.530588853;
    final ref = DateTime.utc(2000, 1, 6, 18, 14);
    final days = now.toUtc().difference(ref).inSeconds / 86400;
    final age = ((days % synodic) + synodic) % synodic / synodic;
    return (lit: (1 - math.cos(2 * math.pi * age)) / 2, waxing: age < 0.5);
  }
}

/// Fundo animado da tela Correr: céu do momento, sol ou lua, nuvens, aves,
/// vento, estrelas, vaga-lumes e morros com capim balançando.
class SkyScene extends StatefulWidget {
  final SkyInfo info;
  final double lat;

  /// Rolagem da tela, para o efeito de profundidade.
  final ValueListenable<double>? scroll;

  /// Altura (em dp, a partir do topo) onde começam os morros.
  final double horizon;
  final bool animate;

  const SkyScene({super.key, required this.info, this.lat = SkyInfo.defaultLat, this.scroll, this.horizon = 430, this.animate = true});

  @override
  State<SkyScene> createState() => _SkySceneState();
}

class _SkySceneState extends State<SkyScene> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _time = ValueNotifier<double>(6.5);
  Duration _lastTick = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((d) {
      // ~30 quadros por segundo bastam e poupam bateria.
      if ((d - _lastTick).inMilliseconds < 33) return;
      _lastTick = d;
      _time.value = 6.5 + d.inMicroseconds / 1e6;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(SkyScene old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final run = widget.animate && motionOn(context);
    if (run && !_ticker.isActive) {
      _lastTick = Duration.zero;
      _ticker.start();
    } else if (!run && _ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scroll = widget.scroll ?? ValueNotifier(0.0);
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _ScenePainter(widget.info, _time, scroll, widget.horizon, widget.lat < 0),
        ),
      ),
    );
  }
}

class _ScenePainter extends CustomPainter {
  final SkyInfo info;
  final ValueListenable<double> time;
  final ValueListenable<double> scroll;
  final double horizon;
  final bool south;
  _ScenePainter(this.info, this.time, this.scroll, this.horizon, this.south)
      : super(repaint: Listenable.merge([time, scroll]));

  static double _r(int i) {
    final v = math.sin(i * 999.13 + 0.71) * 43758.5453;
    return v - v.floorToDouble();
  }

  @override
  void paint(Canvas canvas, Size s) {
    final t = time.value;
    final sc = scroll.value.clamp(0.0, 2000.0);
    final l = info.look;
    final mo = info.moment;
    final w = s.width;
    final skyShift = -sc * 0.18;
    final hillShift = -sc * 0.45;
    final hz = horizon + hillShift;

    // Céu.
    final skyRect = Rect.fromLTWH(0, 0, w, math.max(hz + 120, 10));
    canvas.drawRect(
      Offset.zero & s,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [l.top, l.mid, l.low],
          stops: const [0, 0.55, 1],
        ).createShader(skyRect),
    );

    canvas.save();
    canvas.translate(0, skyShift);

    // Brilho no horizonte de manhãzinha.
    if (mo == SkyMoment.aurora || mo == SkyMoment.sunrise || mo == SkyMoment.dusk) {
      final c = Offset(w * 0.62, horizon + 10);
      canvas.drawCircle(
        c,
        w * 0.9,
        Paint()
          ..shader = RadialGradient(colors: [
            l.sun.withValues(alpha: mo == SkyMoment.sunrise ? 0.35 : 0.28),
            l.sun.withValues(alpha: 0),
          ]).createShader(Rect.fromCircle(center: c, radius: w * 0.9)),
      );
    }

    // Estrelas piscando.
    if (l.stars > 0.01) {
      final p = Paint();
      for (var i = 0; i < 90; i++) {
        final x = _r(i) * w;
        final y = _r(i + 300) * horizon * 0.85;
        final tw = 0.35 + 0.65 * (0.5 + 0.5 * math.sin(t * (0.8 + _r(i + 600) * 1.6) + i));
        final big = _r(i + 900) > 0.92;
        p.color = Colors.white.withValues(alpha: (l.stars * tw * (big ? 1 : 0.75)).clamp(0, 1));
        canvas.drawCircle(Offset(x, y), big ? 1.7 : 0.6 + _r(i + 1200) * 0.8, p);
        if (big && l.stars > 0.6) {
          final g = Paint()
            ..color = Colors.white.withValues(alpha: 0.25 * tw * l.stars)
            ..strokeWidth = 0.8;
          canvas.drawLine(Offset(x - 4, y), Offset(x + 4, y), g);
          canvas.drawLine(Offset(x, y - 4), Offset(x, y + 4), g);
        }
      }
    }

    // Estrela cadente de vez em quando.
    if (mo == SkyMoment.night) {
      final cycle = (t / 9).floor();
      final k = (t % 9) / 1.1;
      if (k < 1) {
        final sx = w * (0.1 + _r(cycle) * 0.5), sy = 30 + _r(cycle + 50) * 110;
        final head = Offset(sx + k * 150, sy + k * 70);
        final tail = Offset(head.dx - 70, head.dy - 33);
        canvas.drawLine(
          tail,
          head,
          Paint()
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round
            ..shader = LinearGradient(colors: [
              Colors.white.withValues(alpha: 0),
              Colors.white.withValues(alpha: (1 - k) * 0.95),
            ]).createShader(Rect.fromPoints(tail, head)),
        );
      }
    }

    // Vênus no crepúsculo e na aurora.
    if (mo == SkyMoment.dusk || mo == SkyMoment.aurora) {
      final c = Offset(w * 0.58, horizon * 0.42);
      final a = 0.75 + 0.25 * math.sin(t * 1.7);
      canvas.drawCircle(c, 9, Paint()..color = Colors.white.withValues(alpha: 0.16 * a));
      canvas.drawCircle(c, 2.6, Paint()..color = Colors.white.withValues(alpha: a));
    }

    // Lua (fase real; no hemisfério sul a parte iluminada inverte).
    if (mo == SkyMoment.night || mo == SkyMoment.dusk || mo == SkyMoment.aurora) {
      _moon(canvas, Offset(w * 0.8, 120), 30, l, t);
    }

    // Sol: nasce atrás dos morros, sobe e desce ao longo do dia.
    final sr = info.sun.sunrise, ss = info.sun.sunset;
    final span = ss.difference(sr).inSeconds;
    final p = span <= 0 ? 0.5 : info.now.difference(sr).inSeconds / span;
    if (p > -0.04 && p < 1.04) {
      final elev = math.sin(math.pi * p.clamp(0.0, 1.0));
      final top = 105.0;
      final low = horizon + 26;
      final c = Offset(w * (0.76 + 0.1 * p.clamp(0.0, 1.0)), low - (low - top) * math.pow(elev, 0.75));
      final big = mo == SkyMoment.sunset || mo == SkyMoment.sunrise;
      final r = big ? 44.0 : 36.0;
      if (mo == SkyMoment.sunrise || mo == SkyMoment.sunset) {
        // Raios girando devagar.
        canvas.save();
        canvas.translate(c.dx, c.dy);
        canvas.rotate(t * 0.05);
        final ray = Paint()..color = l.sun.withValues(alpha: 0.10);
        for (var i = 0; i < 14; i++) {
          canvas.rotate(math.pi / 7);
          final path = Path()
            ..moveTo(0, 0)
            ..lineTo(w * 0.9, -26)
            ..lineTo(w * 0.9, 26)
            ..close();
          canvas.drawPath(path, ray);
        }
        canvas.restore();
      }
      final pulse = 1 + 0.04 * math.sin(t * 1.3);
      canvas.drawCircle(c, r * 2.3 * pulse, Paint()..color = l.sun.withValues(alpha: 0.12));
      canvas.drawCircle(c, r * 1.55 * pulse, Paint()..color = l.sun.withValues(alpha: 0.2));
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.3, -0.3),
            colors: [Color.lerp(l.sun, Colors.white, 0.45)!, l.sun],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }

    // Nuvens em camadas, cada uma numa velocidade.
    if (l.cloudAlpha > 0.03) {
      final specs = [
        (y: 150.0, s: 1.0, v: 7.0, o: 0.0),
        (y: 235.0, s: 0.7, v: 4.5, o: 0.45),
        (y: 90.0, s: 0.55, v: 3.0, o: 0.75),
        (y: 300.0, s: 0.85, v: 6.0, o: 0.2),
      ];
      for (final c in specs) {
        final span = w + 260;
        final x = ((c.o * span + t * c.v) % span) - 160;
        _cloud(canvas, Offset(x, c.y), c.s, l.cloud.withValues(alpha: l.cloudAlpha * (0.6 + 0.4 * c.s)));
      }
    }

    // Rajadas de vento.
    if (mo == SkyMoment.day || mo == SkyMoment.sunrise) {
      for (var i = 0; i < 3; i++) {
        final k = ((t * 0.12 + i * 0.37) % 1);
        if (k > 0.55) continue;
        final q = k / 0.55;
        final x0 = -120 + q * (w + 240);
        final y0 = 250 + i * 48 + math.sin(t + i) * 6;
        final path = Path()
          ..moveTo(x0, y0)
          ..cubicTo(x0 + 40, y0 - 12, x0 + 80, y0 + 12, x0 + 120, y0)
          ..cubicTo(x0 + 135, y0 - 5, x0 + 140, y0 - 16, x0 + 128, y0 - 18);
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round
            ..color = Colors.white.withValues(alpha: 0.55 * math.sin(q * math.pi)),
        );
      }
    }

    // Aves.
    final birdColor = info.onSky == Colors.white
        ? Colors.white.withValues(alpha: 0.75)
        : Color.lerp(PaceColors.ink, l.top, 0.35)!.withValues(alpha: 0.7);
    if (mo == SkyMoment.sunrise) {
      final k = (t / 28) % 1;
      final bx = -90 + k * (w + 180), by = 270 - k * 110;
      const v = [(0.0, 0.0), (-22.0, 13.0), (22.0, 13.0), (-44.0, 26.0), (44.0, 26.0), (-66.0, 39.0)];
      for (var i = 0; i < v.length; i++) {
        _bird(canvas, Offset(bx + v[i].$1, by + v[i].$2), 9, t * 7 + i * 0.7, birdColor);
      }
    } else if (mo == SkyMoment.day) {
      final k = (t / 34) % 1;
      final flap = (t % 6) < 1.4 ? t * 8 : math.pi / 2;
      _bird(canvas, Offset(-50 + k * (w + 100), 205 + math.sin(t * 0.6) * 18), 13, flap, birdColor);
      final k2 = ((t + 15) / 40) % 1;
      _bird(canvas, Offset(w + 40 - k2 * (w + 80), 120 + math.sin(t * 0.5 + 1) * 10), 8, t * 7, birdColor.withValues(alpha: 0.5));
    } else if (mo == SkyMoment.sunset) {
      final k = (t / 24) % 1;
      const v = [(0.0, 0.0), (34.0, 16.0), (78.0, 6.0)];
      for (var i = 0; i < v.length; i++) {
        _bird(canvas, Offset(w + 60 - k * (w + 220) + v[i].$1, 300 - k * 40 + v[i].$2), 10, t * 6.5 + i, birdColor);
      }
    }
    canvas.restore();

    // Morros (três camadas) e chão.
    _hill(canvas, w, hz - 6, 18, 0.0, l.hillFar, s.height);
    // Névoa de manhãzinha entre os morros.
    if (mo == SkyMoment.aurora || mo == SkyMoment.sunrise) {
      final m = Paint()..color = Colors.white.withValues(alpha: mo == SkyMoment.aurora ? 0.16 : 0.22);
      for (var i = 0; i < 3; i++) {
        final x = ((t * 6 + i * 260) % (w + 400)) - 200;
        canvas.drawOval(Rect.fromCenter(center: Offset(x, hz + 26 + i * 6), width: 300, height: 26), m);
      }
    }
    _hill(canvas, w, hz + 32, 22, 1.7, l.hillMid, s.height);
    final nearY = hz + 78;
    _hill(canvas, w, nearY, 16, 3.1, l.hillNear, s.height);
    canvas.drawRect(
      Rect.fromLTWH(0, nearY + 40, w, s.height),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [l.hillNear, l.ground],
          stops: const [0, 1],
        ).createShader(Rect.fromLTWH(0, nearY + 40, w, 260)),
    );

    // Capim balançando no morro da frente.
    final grass = Paint()
      ..color = Color.lerp(l.hillNear, Colors.black, 0.18)!
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    for (double x = 6; x < w; x += 11) {
      final base = Offset(x, _hillY(x, w, nearY, 16, 3.1) + 3);
      final hgt = 7 + _r(x.toInt()) * 7;
      final sway = math.sin(t * 1.6 + x * 0.045) * 0.22 + 0.08;
      canvas.drawLine(base, base + Offset(math.sin(sway) * hgt, -math.cos(sway) * hgt), grass);
    }

    // Vaga-lumes.
    if (mo == SkyMoment.night || mo == SkyMoment.dusk) {
      final amount = mo == SkyMoment.night ? 1.0 : 0.5;
      for (var i = 0; i < 16; i++) {
        final a = math.max(0.0, math.sin(t * (0.9 + _r(i + 40) * 0.8) + i * 2.1));
        if (a <= 0) continue;
        final c = Offset(
          _r(i + 70) * w + math.sin(t * 0.5 + i) * 14,
          hz + 30 + _r(i + 90) * 130 + math.cos(t * 0.4 + i) * 9,
        );
        canvas.drawCircle(c, 7, Paint()..color = const Color(0xFFE6FF8A).withValues(alpha: 0.18 * a * amount));
        canvas.drawCircle(c, 2, Paint()..color = const Color(0xFFF0FFB0).withValues(alpha: 0.95 * a * amount));
      }
    }
  }

  double _hillY(double x, double w, double y, double amp, double ph) =>
      y + math.sin(x / w * math.pi * 2.2 + ph) * amp + math.sin(x / w * math.pi * 5.1 + ph * 2) * amp * 0.35;

  void _hill(Canvas canvas, double w, double y, double amp, double ph, Color c, double h) {
    final path = Path()..moveTo(0, h);
    for (double x = 0; x <= w + 8; x += 8) {
      path.lineTo(x, _hillY(x, w, y, amp, ph));
    }
    path
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(path, Paint()..color = c);
  }

  void _cloud(Canvas canvas, Offset o, double s, Color c) {
    final p = Paint()..color = c;
    final parts = [(0.0, 0.0, 34.0), (30.0, -14.0, 30.0), (60.0, -4.0, 26.0), (86.0, 4.0, 18.0), (-26.0, 6.0, 18.0)];
    final path = Path();
    for (final q in parts) {
      path.addOval(Rect.fromCircle(center: o + Offset(q.$1 * s * 1.2, q.$2 * s), radius: q.$3 * s));
    }
    path.addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(o.dx - 30 * s, o.dy, 135 * s, 20 * s), Radius.circular(10 * s)));
    canvas.drawPath(path, p);
  }

  void _bird(Canvas canvas, Offset c, double s, double phase, Color color) {
    final f = math.sin(phase) * s * 0.55;
    final path = Path()
      ..moveTo(c.dx - s, c.dy - f)
      ..quadraticBezierTo(c.dx - s * 0.45, c.dy - s * 0.35 - f * 0.3, c.dx, c.dy)
      ..quadraticBezierTo(c.dx + s * 0.45, c.dy - s * 0.35 - f * 0.3, c.dx + s, c.dy - f);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  void _moon(Canvas canvas, Offset c, double r, SkyLook l, double t) {
    final m = info.moon;
    const lit = Color(0xFFF3EFDB);
    final dark = Color.lerp(l.top, Colors.white, 0.12)!;
    canvas.drawCircle(c, r * 2.6, Paint()..color = lit.withValues(alpha: 0.05 + 0.1 * m.lit));
    canvas.drawCircle(c, r * 1.5, Paint()..color = lit.withValues(alpha: 0.06 + 0.1 * m.lit));
    canvas.drawCircle(c, r, Paint()..color = dark);
    // Lado iluminado: crescente fica à direita no norte e à esquerda no sul.
    final rightLit = m.waxing != south;
    final rect = Rect.fromCircle(center: c, radius: r);
    final half = Path()..addArc(rect, rightLit ? -math.pi / 2 : math.pi / 2, math.pi);
    half.close();
    canvas.drawPath(half, Paint()..color = lit);
    final ew = r * (1 - 2 * m.lit).abs();
    final ell = Rect.fromCenter(center: c, width: ew * 2, height: r * 2);
    if (m.lit < 0.5) {
      // Crescente: tira um meio-elipse do lado claro.
      canvas.drawPath(
        Path()..addArc(ell, rightLit ? -math.pi / 2 : math.pi / 2, math.pi),
        Paint()..color = dark,
      );
    } else {
      // Gibosa: soma um meio-elipse no lado escuro.
      canvas.drawPath(
        Path()..addArc(ell, rightLit ? math.pi / 2 : -math.pi / 2, math.pi),
        Paint()..color = lit,
      );
    }
    // Crateras suaves.
    final cr = Paint()..color = const Color(0xFFD9D3BC).withValues(alpha: 0.55 * m.lit);
    canvas.drawCircle(c + Offset(-r * 0.3, -r * 0.2), r * 0.16, cr);
    canvas.drawCircle(c + Offset(r * 0.25, r * 0.3), r * 0.11, cr);
    canvas.drawCircle(c + Offset(r * 0.05, -r * 0.45), r * 0.08, cr);
  }

  @override
  bool shouldRepaint(_ScenePainter o) => o.info != info || o.horizon != horizon;
}
