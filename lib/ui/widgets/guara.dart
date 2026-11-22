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

  const Guara({super.key, required this.pose, this.size = 140, this.semanticLabel});

  @override
  State<Guara> createState() => _GuaraState();
}

class _GuaraState extends State<Guara> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: _period(widget.pose));

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
  }

  @override
  void didUpdateWidget(Guara old) {
    super.didUpdateWidget(old);
    if (old.pose != widget.pose) {
      _c.duration = _period(widget.pose);
      if (_c.isAnimating) _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
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
    final pic = SvgPicture.string(_art, width: widget.size, height: widget.size * 170 / 160, fit: BoxFit.contain);
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
