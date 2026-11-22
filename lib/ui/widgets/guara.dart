import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'guara_art.dart';
import 'pace_ui.dart';

/// Poses do mascote Guará (lobo-guará do PACE).
enum GuaraPose { wave, run, celebrate, sleep }

/// O Guará, com uma animação leve conforme a pose
/// (respira acenando, quica correndo, pula comemorando, respira dormindo).
class Guara extends StatefulWidget {
  final GuaraPose pose;
  final double size;
  final String? semanticLabel;

  /// Na pose de aceno: quantas vezes ele balança o braço ao aparecer.
  final int waves;

  /// Mude este número para ele acenar de novo (ex.: ao ser tocado).
  final int waveTrigger;

  const Guara({
    super.key,
    required this.pose,
    this.size = 140,
    this.semanticLabel,
    this.waves = 0,
    this.waveTrigger = 0,
  });

  @override
  State<Guara> createState() => _GuaraState();
}

class _GuaraState extends State<Guara> with TickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: _period(widget.pose));
  late final AnimationController _w = AnimationController(vsync: this);
  bool _greeted = false;

  void _wave(int times) {
    if (times <= 0 || widget.pose != GuaraPose.wave || !motionOn(context)) return;
    _w.duration = Duration(milliseconds: 520 * times);
    _w.forward(from: 0);
  }

  static Duration _period(GuaraPose p) => switch (p) {
        GuaraPose.run => const Duration(milliseconds: 520),
        GuaraPose.celebrate => const Duration(milliseconds: 1200),
        GuaraPose.wave => const Duration(milliseconds: 2400),
        GuaraPose.sleep => const Duration(milliseconds: 3600),
      };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (motionOn(context)) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
    }
    if (!_greeted) {
      _greeted = true;
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted) _wave(widget.waves);
      });
    }
  }

  @override
  void didUpdateWidget(Guara old) {
    super.didUpdateWidget(old);
    if (old.pose != widget.pose) {
      _c.duration = _period(widget.pose);
      if (_c.isAnimating) _c.repeat();
    }
    if (old.waveTrigger != widget.waveTrigger) _wave(math.max(widget.waves, 2));
  }

  @override
  void dispose() {
    _c.dispose();
    _w.dispose();
    super.dispose();
  }

  String get _art => switch (widget.pose) {
        GuaraPose.wave => GuaraArt.wave,
        GuaraPose.run => GuaraArt.run,
        GuaraPose.celebrate => GuaraArt.celebrate,
        GuaraPose.sleep => GuaraArt.sleep,
      };

  String get _label =>
      widget.semanticLabel ??
      switch (widget.pose) {
        GuaraPose.wave => 'Guará, o mascote do PACE, acenando',
        GuaraPose.run => 'Guará correndo',
        GuaraPose.celebrate => 'Guará comemorando com medalha',
        GuaraPose.sleep => 'Guará descansando',
      };

  @override
  Widget build(BuildContext context) {
    final w = widget.size, h = widget.size * 170 / 160;
    Widget pic;
    if (widget.pose == GuaraPose.wave) {
      // Corpo + braço separado, girando no ombro (106,100 no desenho 160x170).
      const pivot = Alignment(2 * 106 / 160 - 1, 2 * 100 / 170 - 1);
      pic = SizedBox(
        width: w,
        height: h,
        child: Stack(
          children: [
            SvgPicture.string(GuaraArt.waveBody, width: w, height: h, fit: BoxFit.contain),
            AnimatedBuilder(
              animation: _w,
              builder: (context, child) {
                final v = _w.value;
                final n = (_w.duration?.inMilliseconds ?? 520) / 520;
                final env = math.sin(v * math.pi).clamp(0.0, 1.0);
                final a = _w.isAnimating ? -0.55 * math.sin(v * n * 2 * math.pi) * (0.4 + 0.6 * env) : 0.0;
                return Transform.rotate(angle: a, alignment: pivot, child: child);
              },
              child: SvgPicture.string(GuaraArt.waveArm, width: w, height: h, fit: BoxFit.contain),
            ),
          ],
        ),
      );
    } else {
      pic = SvgPicture.string(_art, width: w, height: h, fit: BoxFit.contain);
    }
    return Semantics(
      image: true,
      label: _label,
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _c,
          child: pic,
          builder: (context, child) {
            final t = _c.value;
            final s = widget.size / 160;
            switch (widget.pose) {
              case GuaraPose.run:
                return Transform.translate(offset: Offset(0, -5 * s * math.sin(t * math.pi).abs()), child: child);
              case GuaraPose.celebrate:
                final up = t < 0.4 ? math.sin(t / 0.4 * math.pi) : 0.0;
                return Transform.translate(offset: Offset(0, -14 * s * up), child: child);
              case GuaraPose.wave:
              case GuaraPose.sleep:
                return Transform.translate(offset: Offset(0, -4 * s * math.sin(t * 2 * math.pi).abs()), child: child);
            }
          },
        ),
      ),
    );
  }
}
