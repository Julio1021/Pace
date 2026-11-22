import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../domain/coach.dart';
import '../domain/stats.dart';
import '../state/app_state.dart';
import 'widgets/guara.dart';
import 'widgets/pace_ui.dart';

/// Frase do dia do Guará, baseada nos dados reais.
({String text, GuaraPose pose}) introMessage(AppState app, DateTime now) {
  final first = app.profile.name.trim().split(' ').first;
  final hello = now.hour < 12 ? 'Bom dia' : (now.hour < 18 ? 'Boa tarde' : 'Boa noite');
  if (app.activities.isEmpty) {
    return (text: '$hello, $first! Vamos começar? Sua primeira corrida está a um toque.', pose: GuaraPose.wave);
  }
  final week = app.weekStats(now);
  final goal = app.profile.weeklyGoalKm;
  final km = week.distanceM / 1000;
  final last = app.activities.first;
  final lastDay = Periods.dayStart(last.start.toLocal());
  final today = Periods.dayStart(now);
  final daysSince = today.difference(lastDay).inDays;

  if (goal > 0 && km >= goal) {
    return (text: '$hello, $first! Meta da semana batida. Hoje pode ser dia de descanso.', pose: GuaraPose.sleep);
  }
  if (daysSince >= 4) {
    return (text: 'Faz $daysSince dias desde a última corrida. Que tal uma leve hoje?', pose: GuaraPose.wave);
  }
  if (daysSince == 1) {
    return (text: '$hello, $first! Ontem foram ${Fmt.kmUnit(last.distanceM)}. Mandou bem!', pose: GuaraPose.wave);
  }
  final left = goal - km;
  if (goal > 0 && left > 0 && left <= goal * 0.6) {
    return (
      text: '$hello, $first! Faltam só ${Fmt.kmUnit(left * 1000, decimals: 1)} para a meta da semana. Bora?',
      pose: GuaraPose.wave,
    );
  }
  const tips = CoachPhrases.daily;
  final tip = tips[(now.year * 400 + now.month * 31 + now.day) % tips.length];
  return (text: '$hello, $first! $tip', pose: GuaraPose.wave);
}

/// Abertura: o Guará entra correndo, para, acena com a frase do dia e a tela
/// se desfaz no Início. Cerca de 2 s; um toque pula.
class IntroOverlay extends StatefulWidget {
  final VoidCallback onDone;
  const IntroOverlay({super.key, required this.onDone});

  @override
  State<IntroOverlay> createState() => _IntroOverlayState();
}

class _IntroOverlayState extends State<IntroOverlay> with TickerProviderStateMixin {
  late final AnimationController _enter = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  late final AnimationController _bubble = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
  late final AnimationController _out = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
  bool _arrived = false;
  bool _closing = false;
  Timer? _timer;
  late ({String text, GuaraPose pose}) _msg;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _msg = introMessage(context.read<AppState>(), DateTime.now());
    if (!motionOn(context)) {
      _arrived = true;
      _enter.value = 1;
      _bubble.value = 1;
      _timer = Timer(const Duration(milliseconds: 1000), _close);
      return;
    }
    _enter.forward().then((_) {
      if (!mounted) return;
      setState(() => _arrived = true);
      _bubble.forward();
    });
    _timer = Timer(const Duration(milliseconds: 2300), _close);
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    _timer?.cancel();
    if (motionOn(context)) await _out.forward();
    widget.onDone();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _enter.dispose();
    _bubble.dispose();
    _out.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _close,
      child: FadeTransition(
        opacity: Tween(begin: 1.0, end: 0.0).animate(_out),
        child: Material(
          color: PaceColors.bgLight,
          child: Stack(
            children: [
              const Positioned(top: 0, left: 0, right: 0, child: MeshBackground(height: 900)),
              SafeArea(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ScaleTransition(
                        scale: CurvedAnimation(parent: _bubble, curve: Curves.easeOutBack),
                        child: FadeTransition(opacity: _bubble, child: _Bubble(text: _msg.text)),
                      ),
                      const SizedBox(height: 10),
                      AnimatedBuilder(
                        animation: _enter,
                        builder: (context, child) {
                          final t = Curves.easeOutCubic.transform(_enter.value);
                          return Transform.translate(offset: Offset(-(w * 0.75) * (1 - t), 0), child: child);
                        },
                        child: Guara(
                          key: ValueKey(_arrived),
                          pose: _arrived ? _msg.pose : GuaraPose.run,
                          size: 170,
                        ),
                      ),
                      const SizedBox(height: 10),
                      FadeTransition(
                        opacity: _bubble,
                        child: Text('PACE', style: numStyle(24, color: PaceColors.mint).copyWith(letterSpacing: 6)),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: MediaQuery.paddingOf(context).top + 12,
                right: 18,
                child: const Text('Toque para pular',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: PaceColors.muted)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final String text;
  const _Bubble({required this.text});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 290),
          child: GlassCard(
            radius: 20,
            blur: false,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, height: 1.35, fontWeight: FontWeight.w600, color: Colors.white),
            ),
          ),
        ),
        CustomPaint(size: const Size(18, 9), painter: _TailPainter()),
      ],
    );
  }
}

class _TailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(s.width, 0)
      ..lineTo(s.width / 2, s.height)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xF0121720));
  }

  @override
  bool shouldRepaint(_TailPainter old) => false;
}
