import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../services/recorder.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/route_widgets.dart';
import 'activity_detail_screen.dart';

/// Tela da corrida em andamento: números grandes, mapa e controles à prova de toque acidental.
class LiveRunScreen extends StatefulWidget {
  const LiveRunScreen({super.key});

  @override
  State<LiveRunScreen> createState() => _LiveRunScreenState();
}

class _LiveRunScreenState extends State<LiveRunScreen> {
  bool _locked = false;
  bool _showMap = false;
  bool _finishing = false;
  double _holdProgress = 0;
  final _map = MapController();
  int _lastPointCount = 0;

  Future<void> _finish() async {
    if (_finishing) return;
    final rec = context.read<Recorder>();
    final app = context.read<AppState>();
    if (rec.distance < 50) {
      final keep = await confirmDialog(
        context,
        title: 'Corrida muito curta',
        message: 'Foram registrados só ${Fmt.integer(rec.distance)} m. Deseja salvar mesmo assim?',
        confirm: 'Salvar',
      );
      if (!keep) return;
    }
    setState(() => _finishing = true);
    final id = await rec.finish();
    await app.reload();
    rec.clear();
    if (!mounted || id == null) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => ActivityDetailScreen(activityId: id, justFinished: true)),
    );
  }

  Future<void> _discard() async {
    final ok = await confirmDialog(
      context,
      title: 'Descartar corrida?',
      message: 'Tudo o que foi gravado nesta corrida será apagado.',
      confirm: 'Descartar',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await context.read<Recorder>().discard();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final rec = context.watch<Recorder>();
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final paused = rec.manuallyPaused || rec.autoPaused;

    if (!rec.isActive && !_finishing) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Nenhuma corrida em andamento.')),
      );
    }

    final route = rec.points.where((p) => !p.paused).map((p) => LatLng(p.lat, p.lon)).toList();
    final current = rec.points.isEmpty ? null : LatLng(rec.points.last.lat, rec.points.last.lon);
    if (_showMap && current != null && rec.points.length != _lastPointCount) {
      _lastPointCount = rec.points.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          _map.move(current, _map.camera.zoom);
        } catch (_) {}
      });
    }

    return PopScope(
      canPop: !_locked,
      child: Scaffold(
        backgroundColor: dark ? PaceColors.bgDark : PaceColors.bgLight,
        body: SafeArea(
          child: Column(
            children: [
              // Cabeçalho
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Minimizar',
                      onPressed: _locked ? null : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.keyboard_arrow_down),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            rec.manuallyPaused
                                ? 'PAUSADA'
                                : rec.autoPaused
                                    ? 'PAUSA AUTOMÁTICA'
                                    : rec.config.type.toUpperCase(),
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.5,
                              color: paused ? PaceColors.orange : cs.primary,
                            ),
                          ),
                          if (rec.gpsWarning != null)
                            Text(rec.gpsWarning!, style: const TextStyle(fontSize: 12, color: PaceColors.orange)),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: _showMap ? 'Ver números' : 'Ver mapa',
                      onPressed: _locked ? null : () => setState(() => _showMap = !_showMap),
                      icon: Icon(_showMap ? Icons.speed : Icons.map_outlined),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _showMap
                    ? Padding(
                        padding: const EdgeInsets.all(12),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: RouteMap(points: route, current: current, controller: _map),
                        ),
                      )
                    : _Numbers(rec: rec),
              ),
              if (_showMap)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      Expanded(child: _Mini(label: 'Tempo', value: Fmt.duration(rec.moving))),
                      Expanded(child: _Mini(label: 'km', value: Fmt.km(rec.distance))),
                      Expanded(child: _Mini(label: 'Pace', value: Fmt.pace(rec.currentPace))),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              _Controls(
                locked: _locked,
                paused: rec.manuallyPaused,
                finishing: _finishing,
                holdProgress: _holdProgress,
                onLock: () {
                  HapticFeedback.selectionClick();
                  setState(() => _locked = !_locked);
                },
                onPauseResume: () => rec.manuallyPaused ? rec.resume() : rec.pause(),
                onLap: rec.markLap,
                onHold: (v) => setState(() => _holdProgress = v),
                onFinish: _finish,
                onDiscard: _discard,
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _Numbers extends StatelessWidget {
  final Recorder rec;
  const _Numbers({required this.rec});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const tab = [FontFeature.tabularFigures()];
    final goal = rec.goalProgress;
    return LayoutBuilder(builder: (context, c) {
      final big = (c.maxHeight * 0.2).clamp(56.0, 110.0);
      return Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Column(
            children: [
              FittedBox(
                child: Text(Fmt.duration(rec.moving),
                    style: TextStyle(fontSize: big * 0.75, fontWeight: FontWeight.w800, fontFeatures: tab)),
              ),
              Text('Tempo em movimento', style: TextStyle(color: cs.onSurfaceVariant)),
            ],
          ),
          Column(
            children: [
              FittedBox(
                child: Text(Fmt.km(rec.distance),
                    style: TextStyle(fontSize: big, fontWeight: FontWeight.w900, color: cs.primary, height: 1, fontFeatures: tab)),
              ),
              Text('Quilômetros', style: TextStyle(color: cs.onSurfaceVariant)),
            ],
          ),
          if (goal != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: goal,
                      minHeight: 8,
                      color: goal >= 1 ? cs.secondary : cs.primary,
                      backgroundColor: cs.onSurface.withValues(alpha: 0.08),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(goal >= 1 ? 'Meta atingida!' : 'Meta: ${Fmt.percent(goal)}',
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(child: _Mini(label: 'Pace atual', value: Fmt.pace(rec.currentPace), unit: '/km')),
                Expanded(child: _Mini(label: 'Pace médio', value: Fmt.pace(rec.avgPace), unit: '/km')),
                Expanded(child: _Mini(label: 'Velocidade', value: Fmt.speed(rec.avgSpeed), unit: 'km/h')),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(child: _Mini(label: 'Calorias (estim.)', value: Fmt.integer(rec.calories), unit: 'kcal')),
                Expanded(
                  child: _Mini(
                    label: rec.laps.isEmpty ? 'Km atual' : 'Volta ${rec.laps.length + 1}',
                    value: Fmt.km(rec.laps.isEmpty ? rec.distance % 1000 : rec.lapDistance),
                    unit: 'km',
                  ),
                ),
                Expanded(child: _Mini(label: 'Tempo total', value: Fmt.duration(rec.elapsed))),
              ],
            ),
          ),
        ],
      );
    });
  }
}

class _Mini extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  const _Mini({required this.label, required this.value, this.unit});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        FittedBox(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value,
                  style: const TextStyle(
                      fontSize: 28, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
              if (unit != null) ...[
                const SizedBox(width: 2),
                Text(unit!, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ],
          ),
        ),
        Text(label, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant), maxLines: 1),
      ],
    );
  }
}

class _Controls extends StatelessWidget {
  final bool locked;
  final bool paused;
  final bool finishing;
  final double holdProgress;
  final VoidCallback onLock;
  final VoidCallback onPauseResume;
  final VoidCallback onLap;
  final ValueChanged<double> onHold;
  final VoidCallback onFinish;
  final VoidCallback onDiscard;

  const _Controls({
    required this.locked,
    required this.paused,
    required this.finishing,
    required this.holdProgress,
    required this.onLock,
    required this.onPauseResume,
    required this.onLap,
    required this.onHold,
    required this.onFinish,
    required this.onDiscard,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (finishing) return const Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator());
    if (locked) {
      return Column(
        children: [
          _HoldButton(
            size: 84,
            color: cs.onSurface.withValues(alpha: 0.12),
            icon: Icons.lock,
            iconColor: cs.onSurface,
            label: 'Segure para desbloquear',
            onDone: onLock,
          ),
        ],
      );
    }
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _Round(icon: Icons.lock_open, label: 'Bloquear', onTap: onLock),
            _Round(icon: Icons.flag, label: 'Volta', onTap: paused ? null : onLap),
            GestureDetector(
              onTap: onPauseResume,
              child: Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  color: paused ? cs.secondary : PaceColors.orange,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 12, offset: const Offset(0, 4))],
                ),
                child: Icon(paused ? Icons.play_arrow : Icons.pause, size: 48, color: Colors.white),
              ),
            ),
            if (paused)
              _HoldButton(
                size: 64,
                color: PaceColors.red,
                icon: Icons.stop,
                iconColor: Colors.white,
                label: 'Encerrar',
                onDone: onFinish,
              )
            else
              const SizedBox(width: 64),
            _Round(icon: Icons.delete_outline, label: 'Descartar', onTap: paused ? onDiscard : null),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            paused ? 'Segure o botão vermelho para encerrar e salvar' : 'Pause para encerrar ou descartar',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _Round extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _Round({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.35,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton.filledTonal(
            onPressed: onTap,
            iconSize: 26,
            style: IconButton.styleFrom(minimumSize: const Size(52, 52)),
            icon: Icon(icon),
          ),
          Text(label, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// Botão que só dispara depois de segurado por 1,2 s (evita toques acidentais).
class _HoldButton extends StatefulWidget {
  final double size;
  final Color color;
  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback onDone;

  const _HoldButton({
    required this.size,
    required this.color,
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onDone,
  });

  @override
  State<_HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<_HoldButton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        HapticFeedback.heavyImpact();
        widget.onDone();
        _c.reset();
      }
    });

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTapDown: (_) => _c.forward(),
          onTapUp: (_) => _c.reverse(),
          onTapCancel: () => _c.reverse(),
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) => SizedBox(
              width: widget.size,
              height: widget.size,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle)),
                  SizedBox(
                    width: widget.size,
                    height: widget.size,
                    child: CircularProgressIndicator(
                      value: _c.value,
                      strokeWidth: 4,
                      color: cs.primary,
                      backgroundColor: Colors.transparent,
                    ),
                  ),
                  Icon(widget.icon, color: widget.iconColor, size: widget.size * 0.45),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(widget.label, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
      ],
    );
  }
}
