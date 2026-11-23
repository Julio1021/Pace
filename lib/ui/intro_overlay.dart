import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../domain/intro_messages.dart';
import '../state/app_state.dart';
import 'widgets/guara.dart';
import 'widgets/pace_ui.dart';

GuaraPose _pose(GuaraPoseHint h) => switch (h) {
      GuaraPoseHint.wave => GuaraPose.wave,
      GuaraPoseHint.run => GuaraPose.run,
      GuaraPoseHint.celebrate => GuaraPose.celebrate,
      GuaraPoseHint.sleep => GuaraPose.sleep,
    };

/// Abertura: o Guará chega de um jeito diferente a cada vez (correndo, caindo,
/// espiando de baixo, surgindo…), dá o recado do momento e uma dica ou incentivo.
/// Fica o tempo de ler com calma (barrinha mostra o tempo); um toque fecha.
class IntroOverlay extends StatefulWidget {
  final VoidCallback onDone;

  /// Para prints/testes: usa este recado em vez de sortear.
  final IntroMessage? message;
  const IntroOverlay({super.key, required this.onDone, this.message});

  @override
  State<IntroOverlay> createState() => _IntroOverlayState();
}

class _IntroOverlayState extends State<IntroOverlay> with TickerProviderStateMixin {
  late final AnimationController _enter = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  late final AnimationController _bubble = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  late final AnimationController _tip = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  late final AnimationController _read = AnimationController(vsync: this);
  late final AnimationController _out = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
  bool _arrived = false;
  bool _closing = false;
  bool _started = false;
  late IntroMessage _msg;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _msg = widget.message ?? context.read<AppState>().pickIntro(DateTime.now());
    _read.duration = _msg.readingTime;
    _read.addStatusListener((s) {
      if (s == AnimationStatus.completed) _close();
    });
    if (!motionOn(context)) {
      _arrived = true;
      _enter.value = 1;
      _bubble.value = 1;
      _tip.value = 1;
      _read.forward();
      return;
    }
    _enter.forward().then((_) async {
      if (!mounted) return;
      setState(() => _arrived = true);
      await _bubble.forward();
      if (!mounted) return;
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
      _tip.forward();
      _read.forward();
    });
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    _read.stop();
    if (motionOn(context)) await _out.forward();
    widget.onDone();
  }

  @override
  void dispose() {
    for (final c in [_enter, _bubble, _tip, _read, _out]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Posição do Guará durante a entrada, conforme o modo sorteado.
  Widget _entrance(Widget child, double w, double h) {
    return AnimatedBuilder(
      animation: _enter,
      child: child,
      builder: (context, child) {
        final v = _enter.value;
        switch (_msg.entrance) {
          case IntroEntrance.runIn:
            final t = Curves.easeOutCubic.transform(v);
            return Transform.translate(offset: Offset(-(w * 0.8) * (1 - t), 0), child: child);
          case IntroEntrance.runInRight:
            final t = Curves.easeOutCubic.transform(v);
            return Transform.translate(
              offset: Offset((w * 0.8) * (1 - t), 0),
              child: Transform.flip(flipX: !_arrived, child: child),
            );
          case IntroEntrance.drop:
            final t = Curves.bounceOut.transform(v);
            return Transform.translate(offset: Offset(0, -h * 0.6 * (1 - t)), child: child);
          case IntroEntrance.peek:
            final t = Curves.easeOutBack.transform(v);
            return Transform.translate(offset: Offset(0, 220 * (1 - t)), child: Opacity(opacity: v.clamp(0, 1), child: child));
          case IntroEntrance.pop:
            final t = Curves.elasticOut.transform(v);
            return Transform.scale(scale: t.clamp(0.0, 1.3), child: Transform.rotate(angle: (1 - v) * 0.6, child: child));
        }
      },
    );
  }

  GuaraPose get _movingPose => switch (_msg.entrance) {
        IntroEntrance.runIn || IntroEntrance.runInRight => GuaraPose.run,
        IntroEntrance.drop || IntroEntrance.pop => GuaraPose.celebrate,
        IntroEntrance.peek => _pose(_msg.pose),
      };

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
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
                  child: SingleChildScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ScaleTransition(
                          scale: CurvedAnimation(parent: _bubble, curve: Curves.easeOutBack),
                          child: FadeTransition(
                            opacity: _bubble,
                            child: _Bubble(title: _msg.title, text: _msg.text, progress: _read),
                          ),
                        ),
                        const SizedBox(height: 8),
                        _entrance(
                          Guara(
                            key: ValueKey(_arrived),
                            pose: _arrived ? _pose(_msg.pose) : _movingPose,
                            size: 160,
                            waves: _arrived ? 2 : 0,
                          ),
                          size.width,
                          size.height,
                        ),
                        const SizedBox(height: 14),
                        SlideTransition(
                          position: Tween(begin: const Offset(0, 0.25), end: Offset.zero)
                              .animate(CurvedAnimation(parent: _tip, curve: Curves.easeOutCubic)),
                          child: FadeTransition(opacity: _tip, child: _TipCard(text: _msg.tip, advice: _msg.tipIsAdvice)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: pad.top + 6,
                right: 8,
                child: TextButton(
                  onPressed: _close,
                  child: const Text('Pular', style: TextStyle(fontWeight: FontWeight.w700, color: PaceColors.muted)),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: pad.bottom + 18,
                child: FadeTransition(
                  opacity: _tip,
                  child: const Text(
                    'Toque para continuar · Ajuste em Perfil › Animação de abertura',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: PaceColors.muted),
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

class _Bubble extends StatelessWidget {
  final String title;
  final String text;
  final Animation<double> progress;
  const _Bubble({required this.title, required this.text, required this.progress});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: GlassCard(
            radius: 22,
            blur: false,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, textAlign: TextAlign.center, style: numStyle(20, color: PaceColors.mintBright)),
                const SizedBox(height: 6),
                Text(
                  text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16.5, height: 1.4, fontWeight: FontWeight.w600, color: Colors.white),
                ),
                const SizedBox(height: 12),
                // Quanto tempo falta para fechar sozinho.
                AnimatedBuilder(
                  animation: progress,
                  builder: (context, _) => ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: 1 - progress.value,
                      minHeight: 3,
                      color: PaceColors.mintBright.withValues(alpha: 0.8),
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        CustomPaint(size: const Size(18, 9), painter: _TailPainter()),
      ],
    );
  }
}

class _TipCard extends StatelessWidget {
  final String text;
  final bool advice;
  const _TipCard({required this.text, required this.advice});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: PaceColors.mint.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(color: PaceColors.mint.withValues(alpha: 0.14), shape: BoxShape.circle),
              child: Icon(advice ? Icons.lightbulb_outline_rounded : Icons.favorite_border_rounded, size: 18, color: PaceColors.mintDark),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(advice ? 'Dica do Guará' : 'Para hoje',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: PaceColors.mintDark)),
                  const SizedBox(height: 2),
                  Text(text, style: const TextStyle(fontSize: 14.5, height: 1.35, color: PaceColors.ink)),
                ],
              ),
            ),
          ],
        ),
      ),
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
