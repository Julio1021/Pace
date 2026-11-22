import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Animações ligadas? (respeita "remover animações" da acessibilidade).
bool motionOn(BuildContext context) => !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);

/// Entrada suave (sobe e aparece), tocada uma única vez.
class Appear extends StatefulWidget {
  final Widget child;
  final int delayMs;
  const Appear({super.key, required this.child, this.delayMs = 0});

  @override
  State<Appear> createState() => _AppearState();
}

class _AppearState extends State<Appear> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 550));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!motionOn(context)) {
      _c.value = 1;
    } else {
      Future<void>.delayed(Duration(milliseconds: widget.delayMs), () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return AnimatedBuilder(
      animation: curve,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: curve.value,
        child: Transform.translate(offset: Offset(0, 14 * (1 - curve.value)), child: child),
      ),
    );
  }
}

/// Tema escuro usado dentro dos cartões de vidro fumê (textos claros).
final ThemeData glassTheme = buildTheme(Brightness.dark);

/// Cartão de "vidro fumê": grafite translúcido com brilho diagonal suave,
/// filete de luz no topo e borda fina. O conteúdo usa o tema escuro.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double radius;
  final bool blur;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
    this.radius = 24,
    this.blur = true,
  });

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    final body = Theme(
      data: glassTheme,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          splashColor: Colors.white.withValues(alpha: 0.06),
          highlightColor: Colors.white.withValues(alpha: 0.04),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
    final tinted = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xD6222934), Color(0xE6121720)],
        ),
      ),
      child: DecoratedBox(
        // Brilho diagonal do vidro.
        decoration: BoxDecoration(
          borderRadius: r,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: const Alignment(0.2, 0.4),
            colors: [Colors.white.withValues(alpha: 0.10), Colors.white.withValues(alpha: 0.0)],
          ),
        ),
        child: body,
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: const [
          BoxShadow(color: Color(0x1F0F172A), blurRadius: 18, offset: Offset(0, 8)),
          BoxShadow(color: Color(0x140F172A), blurRadius: 4, offset: Offset(0, 1)),
        ],
      ),
      child: ClipRRect(
        borderRadius: r,
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: r,
            border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
          ),
          child: Stack(
            // Passa a largura do pai: sem isso o vidro encolhia até o conteúdo
            // e a sombra ficava "sobrando" ao lado (cards Tempo/Pace/kcal).
            fit: StackFit.passthrough,
            children: [
              blur ? BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10), child: tinted) : tinted,
              // Filete de luz no topo (borda do vidro).
              Positioned(
                left: radius * 0.6,
                right: radius * 0.6,
                top: 0,
                child: Container(
                  height: 1,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      Colors.white.withValues(alpha: 0),
                      Colors.white.withValues(alpha: 0.28),
                      Colors.white.withValues(alpha: 0),
                    ]),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Número que "rola" até o valor final.
class CountUp extends StatelessWidget {
  final double value;
  final String Function(double) format;
  final TextStyle style;
  final int ms;

  const CountUp({super.key, required this.value, required this.format, required this.style, this.ms = 1100});

  @override
  Widget build(BuildContext context) {
    if (!motionOn(context)) return Text(format(value), style: style, maxLines: 1);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: Duration(milliseconds: ms),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text(format(v), style: style, maxLines: 1),
    );
  }
}

/// Anel de progresso animado.
class ProgressRing extends StatelessWidget {
  final double progress; // 0..1
  final double size;
  final double stroke;
  final Color color;
  final Color track;
  final Widget? center;

  const ProgressRing({
    super.key,
    required this.progress,
    required this.color,
    required this.track,
    this.size = 128,
    this.stroke = 14,
    this.center,
  });

  @override
  Widget build(BuildContext context) {
    final target = progress.clamp(0.0, 1.0);
    Widget ring(double v) => CustomPaint(
          size: Size.square(size),
          painter: _RingPainter(v, color, track, stroke),
          child: SizedBox.square(dimension: size, child: Center(child: center)),
        );
    if (!motionOn(context)) return ring(target);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: target),
      duration: const Duration(milliseconds: 1300),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => ring(v),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double v;
  final Color color;
  final Color track;
  final double stroke;
  _RingPainter(this.v, this.color, this.track, this.stroke);

  @override
  void paint(Canvas canvas, Size size) {
    final r = (size.shortestSide - stroke) / 2;
    final c = size.center(Offset.zero);
    final base = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawCircle(c, r, base);
    if (v <= 0) return;
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2, 2 * math.pi * v, false, p);
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.v != v || o.color != color || o.track != track;
}

/// Cartão de medida com ícone colorido (tempo, pace, calorias…).
class MetricCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color soft;
  final Widget value;
  final String label;

  const MetricCard({super.key, required this.icon, required this.color, required this.soft, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    const p = Pal(true);
    return GlassCard(
      radius: 20,
      padding: const EdgeInsets.fromLTRB(12, 14, 10, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: soft, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(height: 10),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: value),
          const SizedBox(height: 2),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.muted, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

/// Selo arredondado (pílula).
class Pill extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  final IconData? icon;
  const Pill({super.key, required this.text, required this.bg, required this.fg, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 13, color: fg), const SizedBox(width: 5)],
          Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
        ],
      ),
    );
  }
}

/// Título de tela grande (Space Grotesk).
class ScreenTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  const ScreenTitle(this.title, {super.key, this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (subtitle != null)
                Text(subtitle!, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.muted)),
              Text(title, style: numStyle(28, color: p.ink)),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Fundos
// ---------------------------------------------------------------------------

/// Fundo "Rota viva": o traçado da última corrida desenhado ao fundo, com um
/// ponto percorrendo o caminho. Sem rota, mostra só o fundo neutro.
class RouteBackground extends StatefulWidget {
  final List<List<double>> points;
  final double height;
  const RouteBackground({super.key, required this.points, this.height = 620});

  @override
  State<RouteBackground> createState() => _RouteBackgroundState();
}

class _RouteBackgroundState extends State<RouteBackground> with TickerProviderStateMixin {
  late final AnimationController _trace = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));
  late final AnimationController _dot = AnimationController(vsync: this, duration: const Duration(seconds: 14));
  bool _init = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    if (motionOn(context)) {
      _trace.forward().then((_) {
        if (mounted) _dot.repeat();
      });
    } else {
      _trace.value = 1;
    }
  }

  @override
  void dispose() {
    _trace.dispose();
    _dot.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    if (widget.points.length < 2) return const SizedBox.shrink();
    return IgnorePointer(
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: Listenable.merge([_trace, _dot]),
            builder: (context, _) => CustomPaint(
              painter: _RouteBgPainter(
                widget.points,
                p.mint,
                Curves.easeOutCubic.transform(_trace.value),
                _trace.isCompleted ? _dot.value : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RouteBgPainter extends CustomPainter {
  final List<List<double>> pts;
  final Color color;
  final double t;
  final double? dot;
  _RouteBgPainter(this.pts, this.color, this.t, this.dot);

  @override
  void paint(Canvas canvas, Size size) {
    final path = fitRoutePath(pts, size, pad: size.width * 0.12);
    if (path == null) return;
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: 0.12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 16
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    final line = Paint()
      ..color = color.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final m in path.computeMetrics()) {
      canvas.drawPath(m.extractPath(0, m.length * t), line);
      final d = dot;
      if (d != null) {
        final pos = m.getTangentForOffset(m.length * d)?.position;
        if (pos != null) {
          canvas.drawCircle(pos, 11, Paint()..color = color.withValues(alpha: 0.18));
          canvas.drawCircle(pos, 5.5, Paint()..color = color);
        }
      }
      break;
    }
  }

  @override
  bool shouldRepaint(_RouteBgPainter o) => o.t != t || o.dot != dot || o.color != color || o.pts != pts;
}

/// Ajusta um trajeto (lat/lon) ao tamanho dado, mantendo a proporção.
Path? fitRoutePath(List<List<double>> pts, Size size, {double pad = 16}) {
  if (pts.length < 2) return null;
  var minLat = pts.first[0], maxLat = pts.first[0], minLon = pts.first[1], maxLon = pts.first[1];
  for (final p in pts) {
    minLat = math.min(minLat, p[0]);
    maxLat = math.max(maxLat, p[0]);
    minLon = math.min(minLon, p[1]);
    maxLon = math.max(maxLon, p[1]);
  }
  final k = math.cos((minLat + maxLat) / 2 * math.pi / 180);
  final w = math.max((maxLon - minLon) * k, 1e-6);
  final h = math.max(maxLat - minLat, 1e-6);
  final scale = math.min((size.width - 2 * pad) / w, (size.height - 2 * pad) / h);
  final ox = (size.width - w * scale) / 2;
  final oy = (size.height - h * scale) / 2;
  Offset map(List<double> p) => Offset(ox + (p[1] - minLon) * k * scale, oy + (maxLat - p[0]) * scale);
  final first = map(pts.first);
  final path = Path()..moveTo(first.dx, first.dy);
  for (final p in pts.skip(1)) {
    final o = map(p);
    path.lineTo(o.dx, o.dy);
  }
  return path;
}

/// "Mosaico do ano": um quadradinho por dia; quanto mais km, mais forte o verde.
class YearMosaic extends StatelessWidget {
  /// km por dia (dia local → km), cobrindo [weeks] semanas até hoje.
  final Map<DateTime, double> kmByDay;
  final int weeks;
  final DateTime today;

  const YearMosaic({super.key, required this.kmByDay, required this.today, this.weeks = 26});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final levels = [p.faint, p.mintMid, p.dark ? const Color(0xFF2BAE82) : const Color(0xFF5ED0A5), p.mint];
    final t = DateTime(today.year, today.month, today.day);
    final lastMonday = t.subtract(Duration(days: t.weekday - 1));
    final first = lastMonday.subtract(Duration(days: 7 * (weeks - 1)));
    int lvl(double km) => km <= 0 ? 0 : (km < 5 ? 1 : (km < 10 ? 2 : 3));
    return LayoutBuilder(builder: (context, c) {
      const gap = 3.0;
      final cell = (c.maxWidth - gap * (weeks - 1)) / weeks;
      return SizedBox(
        height: cell * 7 + gap * 6,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var w = 0; w < weeks; w++) ...[
              if (w > 0) const SizedBox(width: gap),
              Column(
                children: [
                  for (var d = 0; d < 7; d++) ...[
                    if (d > 0) const SizedBox(height: gap),
                    Builder(builder: (_) {
                      final day = DateTime(first.year, first.month, first.day + w * 7 + d);
                      final future = day.isAfter(t);
                      final km = kmByDay[day] ?? 0;
                      return Container(
                        width: cell,
                        height: cell,
                        decoration: BoxDecoration(
                          color: future ? Colors.transparent : levels[lvl(km)],
                          borderRadius: BorderRadius.circular(cell * 0.28),
                          border: day == t ? Border.all(color: p.ink.withValues(alpha: 0.5), width: 1.2) : null,
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ],
          ],
        ),
      );
    });
  }
}

/// Fundo "Degradê vivo": manchas de menta, azul-céu, lilás e pêssego se
/// fundindo e se movendo devagar atrás dos cartões de vidro.
class MeshBackground extends StatefulWidget {
  final double height;
  const MeshBackground({super.key, this.height = 720});

  @override
  State<MeshBackground> createState() => _MeshBackgroundState();
}

class _MeshBackgroundState extends State<MeshBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 18));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (motionOn(context)) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: RepaintBoundary(
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 48, sigmaY: 48, tileMode: TileMode.decal),
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) => CustomPaint(painter: _MeshPainter(_c.value)),
            ),
          ),
        ),
      ),
    );
  }
}

class _MeshPainter extends CustomPainter {
  final double t;
  _MeshPainter(this.t);

  static const _blobs = [
    (color: Color(0xFF8EE6C4), x: 0.05, y: 0.04, r: 0.42, ax: 0.16, ay: 0.08, ph: 0.0, a: 0.75),
    (color: Color(0xFFA9C9FF), x: 0.95, y: 0.08, r: 0.38, ax: -0.18, ay: 0.07, ph: 1.7, a: 0.55),
    (color: Color(0xFFD8C8FF), x: 0.9, y: 0.48, r: 0.36, ax: -0.12, ay: -0.1, ph: 3.1, a: 0.55),
    (color: Color(0xFFFFD6BC), x: 0.08, y: 0.6, r: 0.34, ax: 0.14, ay: -0.08, ph: 4.4, a: 0.5),
  ];

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width;
    final ang = t * 2 * math.pi;
    for (final b in _blobs) {
      final cx = (b.x + b.ax * math.sin(ang + b.ph)) * w;
      final cy = (b.y + b.ay * math.cos(ang * 1.3 + b.ph)) * s.height;
      final r = b.r * w * (1 + 0.1 * math.sin(ang * 0.7 + b.ph));
      canvas.drawCircle(Offset(cx, cy), r, Paint()..color = b.color.withValues(alpha: b.a));
    }
    // Some suavemente para a cor de fundo na parte de baixo.
    final fade = Rect.fromLTWH(0, s.height * 0.55, w, s.height * 0.45);
    canvas.drawRect(
      fade,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00F4F6F9), PaceColors.bgLight],
        ).createShader(fade),
    );
  }

  @override
  bool shouldRepaint(_MeshPainter o) => o.t != t;
}
