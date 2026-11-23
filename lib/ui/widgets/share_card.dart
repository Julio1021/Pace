import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/exporters.dart';
import '../../domain/models.dart';
import 'guara.dart';

enum ShareStyle { night, mint, sunset, sticker }

extension ShareStyleX on ShareStyle {
  String get label => switch (this) {
        ShareStyle.night => 'Noite',
        ShareStyle.mint => 'Menta',
        ShareStyle.sunset => 'Pôr do sol',
        ShareStyle.sticker => 'Adesivo',
      };

  /// Fundo transparente: para colar por cima de uma foto (Stories).
  bool get transparent => this == ShareStyle.sticker;
}

enum ShareFormat { post, story }

/// Imagem da corrida para compartilhar: trajeto, distância, tempo, pace e o Guará.
class ShareCard extends StatelessWidget {
  final Activity activity;
  final ShareStyle style;
  final ShareFormat format;
  final bool showGuara;
  final String? highlight; // ex.: "Novo recorde: 5 km"

  const ShareCard({
    super.key,
    required this.activity,
    this.style = ShareStyle.night,
    this.format = ShareFormat.post,
    this.showGuara = true,
    this.highlight,
  });

  static const width = 360.0;
  double get height => format == ShareFormat.post ? 450 : 640;

  @override
  Widget build(BuildContext context) {
    final a = activity;
    final pts = a.previewPoints;
    final (bg, ink, sub, line) = switch (style) {
      ShareStyle.night => (
          const [Color(0xFF0E1426), Color(0xFF162238), Color(0xFF0B3B33)],
          Colors.white,
          const Color(0xFF9FB3C8),
          PaceColors.mintBright
        ),
      ShareStyle.mint => (
          const [Color(0xFF3DDBA4), Color(0xFF14B887), Color(0xFF0A7E5F)],
          Colors.white,
          const Color(0xFFE2FFF3),
          Colors.white
        ),
      ShareStyle.sunset => (
          const [Color(0xFF8C7DD0), Color(0xFFF5A28A), Color(0xFFFFD3A0)],
          const Color(0xFF25163A),
          const Color(0xFF4E3560),
          Colors.white
        ),
      ShareStyle.sticker => (const <Color>[], Colors.white, Colors.white, PaceColors.mintBright),
    };
    final shadow = style.transparent ? const [Shadow(color: Color(0x99000000), blurRadius: 8)] : const <Shadow>[];
    TextStyle num(double s, {Color? c}) => numStyle(s, color: c ?? ink).copyWith(shadows: shadow, height: 1);
    TextStyle lab() => TextStyle(fontSize: 11.5, color: sub, fontWeight: FontWeight.w700, letterSpacing: 1.2, shadows: shadow);

    Widget metric(String label, String value, String? unit) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label.toUpperCase(), style: lab()),
              const SizedBox(height: 4),
              Text.rich(TextSpan(children: [
                TextSpan(text: value, style: num(22)),
                if (unit != null) TextSpan(text: ' $unit', style: num(12, c: sub)),
              ])),
            ],
          ),
        );

    final story = format == ShareFormat.story;
    return SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(style.transparent ? 0 : 28),
        child: Stack(
          children: [
            if (!style.transparent)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: bg),
                  ),
                ),
              ),
            if (style == ShareStyle.sunset)
              Positioned.fill(child: CustomPaint(painter: _HillsPainter())),
            if (style == ShareStyle.night)
              Positioned.fill(child: CustomPaint(painter: _StarsPainter())),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('PACE', style: num(18).copyWith(letterSpacing: 4)),
                      const Spacer(),
                      Text('${Fmt.date(a.start)} · ${Fmt.time(a.start)}', style: lab().copyWith(letterSpacing: 0.4)),
                    ],
                  ),
                  SizedBox(height: story ? 40 : 10),
                  Expanded(
                    child: pts.length >= 2
                        ? CustomPaint(size: Size.infinite, painter: _GlowRoute(pts, line, style.transparent))
                        : Center(
                            child: showGuara
                                ? const Guara(pose: GuaraPose.run, size: 140)
                                : Icon(Icons.directions_run_rounded, size: 90, color: line),
                          ),
                  ),
                  SizedBox(height: story ? 24 : 8),
                  if (highlight != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFC53D),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.emoji_events_rounded, size: 15, color: Color(0xFF5A3A00)),
                          const SizedBox(width: 5),
                          Text(highlight!,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF5A3A00))),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  Text(a.type.toUpperCase(), style: lab()),
                  const SizedBox(height: 2),
                  Text.rich(TextSpan(children: [
                    TextSpan(text: Fmt.km(a.distanceM), style: num(66)),
                    TextSpan(text: ' km', style: num(26, c: sub)),
                  ])),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      metric('Tempo', Fmt.duration(a.movingSec), null),
                      a.isBike ? metric('Média', Fmt.kmh(a.kmh), 'km/h') : metric('Pace', Fmt.pace(a.paceSecPerKm), '/km'),
                      if (a.elevGain >= 1)
                        metric('Subida', Fmt.integer(a.elevGain), 'm')
                      else
                        metric('Kcal', a.calories == null ? '—' : Fmt.integer(a.calories!), null),
                      if (showGuara && pts.length >= 2) const SizedBox(width: 54),
                    ],
                  ),
                  if (story) const SizedBox(height: 30),
                ],
              ),
            ),
            if (showGuara && pts.length >= 2)
              Positioned(
                right: 12,
                bottom: story ? 40 : 12,
                child: const Guara(pose: GuaraPose.celebrate, size: 74),
              ),
          ],
        ),
      ),
    );
  }
}

/// Trajeto com brilho, ajustado à área (proporção real).
class _GlowRoute extends CustomPainter {
  final List<List<double>> pts;
  final Color color;
  final bool sticker;
  _GlowRoute(this.pts, this.color, this.sticker);

  @override
  void paint(Canvas canvas, Size s) {
    var minLa = double.infinity, maxLa = -double.infinity, minLo = double.infinity, maxLo = -double.infinity;
    for (final p in pts) {
      minLa = math.min(minLa, p[0]);
      maxLa = math.max(maxLa, p[0]);
      minLo = math.min(minLo, p[1]);
      maxLo = math.max(maxLo, p[1]);
    }
    final k = math.cos((minLa + maxLa) / 2 * math.pi / 180);
    final w = math.max((maxLo - minLo) * k, 1e-9), h = math.max(maxLa - minLa, 1e-9);
    final pad = 14.0;
    final scale = math.min((s.width - pad * 2) / w, (s.height - pad * 2) / h);
    final ox = (s.width - w * scale) / 2, oy = (s.height - h * scale) / 2;
    Offset map(List<double> p) => Offset(ox + (p[1] - minLo) * k * scale, oy + (maxLa - p[0]) * scale);
    final path = Path();
    for (var i = 0; i < pts.length; i++) {
      final o = map(pts[i]);
      i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
    }
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (sticker) {
      canvas.drawPath(path, Paint.from(base)
        ..strokeWidth = 9
        ..color = const Color(0x66000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    }
    canvas.drawPath(path, Paint.from(base)
      ..strokeWidth = 14
      ..color = color.withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    canvas.drawPath(path, Paint.from(base)
      ..strokeWidth = 5
      ..color = color);
    final start = map(pts.first), end = map(pts.last);
    canvas.drawCircle(start, 7, Paint()..color = Colors.white);
    canvas.drawCircle(start, 4.5, Paint()..color = PaceColors.mint);
    canvas.drawCircle(end, 7, Paint()..color = Colors.white);
    canvas.drawCircle(end, 4.5, Paint()..color = const Color(0xFFFF5A5F));
  }

  @override
  bool shouldRepaint(_GlowRoute o) => o.pts != pts || o.color != color;
}

class _StarsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final r = math.Random(7);
    final p = Paint();
    for (var i = 0; i < 40; i++) {
      p.color = Colors.white.withValues(alpha: 0.15 + r.nextDouble() * 0.35);
      canvas.drawCircle(Offset(r.nextDouble() * s.width, r.nextDouble() * s.height * 0.6), 0.6 + r.nextDouble() * 1.1, p);
    }
  }

  @override
  bool shouldRepaint(_StarsPainter o) => false;
}

class _HillsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawCircle(Offset(s.width * 0.78, s.height * 0.62), 46, Paint()..color = const Color(0xFFFF8A48).withValues(alpha: 0.85));
    for (final (y, c) in [(0.66, const Color(0x55C8A2C4)), (0.74, const Color(0x6694B49C))]) {
      final path = Path()..moveTo(0, s.height);
      for (double x = 0; x <= s.width; x += 8) {
        path.lineTo(x, s.height * y + math.sin(x / s.width * math.pi * 2.3 + y * 9) * 12);
      }
      path
        ..lineTo(s.width, s.height)
        ..close();
      canvas.drawPath(path, Paint()..color = c);
    }
  }

  @override
  bool shouldRepaint(_HillsPainter o) => false;
}

/// Tela para escolher o estilo e compartilhar a imagem da corrida.
class ShareRunScreen extends StatefulWidget {
  final Activity activity;
  final String? highlight;
  const ShareRunScreen({super.key, required this.activity, this.highlight});

  @override
  State<ShareRunScreen> createState() => _ShareRunScreenState();
}

class _ShareRunScreenState extends State<ShareRunScreen> {
  final _key = GlobalKey();
  ShareStyle _style = ShareStyle.night;
  ShareFormat _format = ShareFormat.post;
  bool _guara = true;
  bool _busy = false;

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      final boundary = _key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final img = await boundary.toImage(pixelRatio: 1080 / ShareCard.width);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return;
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/${exportFileName(widget.activity, 'png')}');
      await f.writeAsBytes(data.buffer.asUint8List());
      await SharePlus.instance.share(ShareParams(
        files: [XFile(f.path, mimeType: 'image/png')],
        text: 'Corri ${Fmt.kmUnit(widget.activity.distanceM)} com o PACE!',
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final card = ShareCard(
      activity: widget.activity,
      style: _style,
      format: _format,
      showGuara: _guara,
      highlight: widget.highlight,
    );
    return Scaffold(
      appBar: AppBar(title: Text(widget.activity.isBike ? 'Compartilhar pedal' : 'Compartilhar corrida')),
      body: Column(
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              // Xadrez discreto atrás do adesivo para mostrar a transparência.
              color: _style.transparent ? const Color(0xFF2B3340) : null,
              padding: const EdgeInsets.all(16),
              child: FittedBox(
                child: RepaintBoundary(key: _key, child: card),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final s in ShareStyle.values)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(s.label),
                              selected: _style == s,
                              onSelected: (_) => setState(() => _style = s),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      SegmentedButton<ShareFormat>(
                        segments: const [
                          ButtonSegment(value: ShareFormat.post, label: Text('Post'), icon: Icon(Icons.crop_portrait)),
                          ButtonSegment(value: ShareFormat.story, label: Text('Stories'), icon: Icon(Icons.smartphone)),
                        ],
                        selected: {_format},
                        onSelectionChanged: (v) => setState(() => _format = v.first),
                      ),
                      const Spacer(),
                      const Text('Guará'),
                      Switch(value: _guara, onChanged: (v) => setState(() => _guara = v)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _busy ? null : _share,
                    icon: const Icon(Icons.ios_share),
                    label: const Text('Compartilhar imagem'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
