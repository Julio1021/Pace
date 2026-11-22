import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../domain/calc.dart';
import '../../domain/models.dart';
import '../../services/recorder.dart';
import '../widgets/common.dart';
import '../widgets/pace_ui.dart';
import 'live_run_screen.dart';

/// Preparação da corrida: permissões, sinal de GPS e opções.
class RunSetupScreen extends StatefulWidget {
  /// Se a aba está visível (liga a prévia do GPS só quando necessário).
  final bool active;
  const RunSetupScreen({super.key, this.active = true});

  @override
  State<RunSetupScreen> createState() => _RunSetupScreenState();
}

class _RunSetupScreenState extends State<RunSetupScreen> with WidgetsBindingObserver {
  GoalType _goal = GoalType.none;
  double _goalKm = 5;
  int _goalMin = 30;
  double _autoLap = 0;
  bool _autoPause = true;
  bool _voice = true;
  String _type = trainingTypes.first;

  LocationPermission? _perm;
  bool _serviceOn = true;
  bool? _batteryOk;
  double? _accuracy;
  StreamSubscription<Position>? _preview;
  bool _visible = false;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _preview?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshStatus();
    } else if (state == AppLifecycleState.paused) {
      _stopPreview();
    }
  }

  bool get _isTabVisible => widget.active;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPreview();
  }

  @override
  void didUpdateWidget(RunSetupScreen old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) _syncPreview();
  }

  void _syncPreview() {
    final rec = context.read<Recorder>();
    final shouldRun = _isTabVisible && _hasPermission && _serviceOn && !rec.isActive;
    if (shouldRun && _preview == null) {
      _preview = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 0),
      ).listen((p) {
        if (mounted) setState(() => _accuracy = p.accuracy);
      }, onError: (Object _) {});
    } else if (!shouldRun && _preview != null) {
      _stopPreview();
    }
    _visible = shouldRun;
  }

  void _stopPreview() {
    _preview?.cancel();
    _preview = null;
  }

  bool get _hasPermission => _perm == LocationPermission.always || _perm == LocationPermission.whileInUse;

  Future<void> _refreshStatus() async {
    LocationPermission perm;
    bool on;
    try {
      perm = await Geolocator.checkPermission();
      on = await Geolocator.isLocationServiceEnabled();
    } catch (_) {
      return; // plataforma sem GPS (ex.: testes)
    }
    bool? battery;
    try {
      battery = await ph.Permission.ignoreBatteryOptimizations.isGranted;
    } catch (_) {
      battery = null;
    }
    if (!mounted) return;
    setState(() {
      _perm = perm;
      _serviceOn = on;
      _batteryOk = battery;
    });
    _syncPreview();
  }

  Future<void> _askLocation() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.location_on_outlined),
        title: const Text('Localização durante a corrida'),
        content: const Text(
          'O PACE usa o GPS para medir distância, pace e desenhar o percurso. '
          'A localização só é usada enquanto uma corrida está sendo gravada e fica salva apenas no seu celular.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Agora não')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Permitir')),
        ],
      ),
    );
    if (ok != true) return;
    final perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
    } else {
      await Geolocator.requestPermission();
    }
    try {
      await ph.Permission.notification.request();
    } catch (_) {}
    await _refreshStatus();
  }

  Future<void> _askBattery() async {
    try {
      await ph.Permission.ignoreBatteryOptimizations.request();
    } catch (_) {
      await ph.openAppSettings();
    }
    await _refreshStatus();
  }

  Future<void> _start({bool force = false}) async {
    if (_starting) return;
    final rec = context.read<Recorder>();
    if (!_hasPermission) {
      await _askLocation();
      if (!_hasPermission) return;
    }
    if (!_serviceOn) {
      await Geolocator.openLocationSettings();
      return;
    }
    final acc = _accuracy;
    if (!force && (acc == null || acc > GpsFilter.maxAccuracyM)) {
      if (!mounted) return;
      final go = await confirmDialog(
        context,
        title: acc == null ? 'Ainda procurando o GPS' : 'Sinal de GPS fraco',
        message: 'Para medir com precisão, espere o sinal ficar "Bom" ao ar livre. '
            'Se iniciar agora, os primeiros metros podem não ser registrados.',
        confirm: 'Iniciar mesmo assim',
      );
      if (!go) return;
    }
    setState(() => _starting = true);
    try {
      try {
        await ph.Permission.notification.request();
      } catch (_) {}
      _stopPreview();
      final cfg = RunConfig(
        goalType: _goal,
        goalValue: switch (_goal) {
          GoalType.distance => _goalKm * 1000,
          GoalType.time => _goalMin * 60.0,
          GoalType.none => 0.0,
        },
        autoLapM: _autoLap,
        autoPause: _autoPause,
        voice: _voice,
        type: _type,
      );
      await rec.start(cfg);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LiveRunScreen()));
    } finally {
      if (mounted) setState(() => _starting = false);
      _syncPreview();
    }
  }

  @override
  Widget build(BuildContext context) {
    final rec = context.watch<Recorder>();
    // Liga/desliga a prévia do GPS quando a aba muda.
    final vis = _isTabVisible && _hasPermission && _serviceOn && !rec.isActive;
    if (vis != _visible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncPreview();
      });
    }

    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    if (rec.isActive) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: EmptyState(
              icon: Icons.directions_run,
              title: 'Corrida em andamento',
              message: 'Volte para a tela da corrida para ver tempo, distância e controles.',
              actions: [
                FilledButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LiveRunScreen())),
                  child: const Text('Abrir corrida'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final quality = GpsFilter.quality(_accuracy);
    final qColor = _accuracy == null
        ? cs.onSurfaceVariant
        : (_accuracy! <= 8 ? Pal.of(context).mintText : (_accuracy! <= 20 ? PaceColors.mintDark : PaceColors.orange));

    final pal = Pal.of(context);
    final now = DateTime.now();
    final phase = SkyBackground.phase(now, pal.dark);
    final onSky = phase.night ? Colors.white : PaceColors.ink;
    return Scaffold(
      body: Stack(
        children: [
          SkyBackground(now: now, height: 560),
          SafeArea(
            bottom: false,
            child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 130),
        children: [
          Appear(
            child: Row(
              children: [
                Expanded(child: Text('Correr', style: numStyle(28, color: onSky))),
                if (_hasPermission && _serviceOn)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(color: pal.card.withValues(alpha: 0.88), borderRadius: BorderRadius.circular(999)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _Blink(color: qColor),
                        const SizedBox(width: 8),
                        Text(
                          _accuracy == null ? 'Procurando GPS…' : 'GPS ${quality.toLowerCase()} · ${_accuracy!.round()} m',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: qColor),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Appear(
            delayMs: 60,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${Fmt.weekdayDate(now.toUtc()).split(',').first} · ${phase.label}',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: onSky.withValues(alpha: 0.75))),
                const SizedBox(height: 2),
                SizedBox(
                  width: 270,
                  child: Text(phase.night ? 'Corrida noturna? Use roupa refletiva.' : 'Bom momento para sair',
                      style: numStyle(30, color: onSky, height: 1.1)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 34),
          Appear(
            delayMs: 120,
            child: Center(
              child: _StartButton(onTap: _starting ? null : () => _start()),
            ),
          ),
          const SizedBox(height: 34),
          if (!_hasPermission)
            _Banner(
              icon: Icons.location_off,
              color: PaceColors.orange,
              text: 'Permita a localização para gravar corridas com GPS.',
              action: 'Permitir',
              onTap: _askLocation,
            )
          else if (!_serviceOn)
            _Banner(
              icon: Icons.location_disabled,
              color: PaceColors.orange,
              text: 'A localização do celular está desligada.',
              action: 'Ligar',
              onTap: () async {
                await Geolocator.openLocationSettings();
              },
            )
          if (_batteryOk == false) ...[
            const SizedBox(height: 10),
            _Banner(
              icon: Icons.battery_alert,
              color: PaceColors.blue,
              text: 'Para não interromper a gravação com a tela bloqueada, desative a otimização de bateria para o PACE.',
              action: 'Ajustar',
              onTap: _askBattery,
            ),
          ],
          const SectionTitle('Treino'),
          PaceCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.category_outlined),
                  title: const Text('Tipo de treino'),
                  trailing: DropdownButton<String>(
                    value: _type,
                    underline: const SizedBox(),
                    items: trainingTypes.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                    onChanged: (v) => setState(() => _type = v ?? _type),
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Meta', style: t.titleSmall),
                      const SizedBox(height: 8),
                      SegmentedButton<GoalType>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: GoalType.none, label: Text('Livre')),
                          ButtonSegment(value: GoalType.distance, label: Text('Distância')),
                          ButtonSegment(value: GoalType.time, label: Text('Tempo')),
                        ],
                        selected: {_goal},
                        onSelectionChanged: (s) => setState(() => _goal = s.first),
                      ),
                      if (_goal == GoalType.distance)
                        _Stepper(
                          label: '${_goalKm.toStringAsFixed(_goalKm == _goalKm.roundToDouble() ? 0 : 1).replaceAll('.', ',')} km',
                          onMinus: _goalKm > 1 ? () => setState(() => _goalKm -= _goalKm > 10 ? 1 : 0.5) : null,
                          onPlus: _goalKm < 100 ? () => setState(() => _goalKm += _goalKm >= 10 ? 1 : 0.5) : null,
                        ),
                      if (_goal == GoalType.time)
                        _Stepper(
                          label: '$_goalMin min',
                          onMinus: _goalMin > 5 ? () => setState(() => _goalMin -= 5) : null,
                          onPlus: _goalMin < 300 ? () => setState(() => _goalMin += 5) : null,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SectionTitle('Durante a corrida'),
          PaceCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.flag_outlined),
                  title: const Text('Volta automática'),
                  trailing: DropdownButton<double>(
                    value: _autoLap,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('Desligada')),
                      DropdownMenuItem(value: 1000, child: Text('A cada 1 km')),
                      DropdownMenuItem(value: 5000, child: Text('A cada 5 km')),
                    ],
                    onChanged: (v) => setState(() => _autoLap = v ?? 0),
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.pause_circle_outline),
                  title: const Text('Pausa automática'),
                  subtitle: const Text('Pausa quando você para (semáforo, por exemplo)'),
                  value: _autoPause,
                  onChanged: (v) => setState(() => _autoPause = v),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.record_voice_over_outlined),
                  title: const Text('Aviso por voz a cada km'),
                  subtitle: const Text('Tempo, distância e pace do km'),
                  value: _voice,
                  onChanged: (v) => setState(() => _voice = v),
                ),
              ],
            ),
          ),
        ],
      ),
          ),
        ],
      ),
    );
  }
}

/// Botão grande de iniciar, com pulso suave.
class _StartButton extends StatefulWidget {
  final VoidCallback? onTap;
  const _StartButton({required this.onTap});

  @override
  State<_StartButton> createState() => _StartButtonState();
}

class _StartButtonState extends State<_StartButton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200));

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
    final p = Pal.of(context);
    return Semantics(
      button: true,
      label: 'Iniciar corrida',
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, child) {
            final t = _c.value;
            return SizedBox(
              width: 230,
              height: 230,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 176 + 54 * t,
                    height: 176 + 54 * t,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: p.mint.withValues(alpha: 0.35 * (1 - t))),
                  ),
                  child!,
                ],
              ),
            );
          },
          child: Container(
            width: 176,
            height: 176,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: p.mint,
              boxShadow: [BoxShadow(color: p.mint.withValues(alpha: 0.45), blurRadius: 36, offset: const Offset(0, 16))],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.play_arrow_rounded, size: 54, color: p.dark ? PaceColors.bgDark : Colors.white),
                Text('INICIAR',
                    style: numStyle(20, color: p.dark ? PaceColors.bgDark : Colors.white).copyWith(letterSpacing: 1)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Ponto piscando (sinal de GPS).
class _Blink extends StatefulWidget {
  final Color color;
  const _Blink({required this.color});

  @override
  State<_Blink> createState() => _BlinkState();
}

class _BlinkState extends State<_Blink> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600), lowerBound: 0.35, upperBound: 1);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (motionOn(context) && !_c.isAnimating) _c.repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _c,
        child: Container(width: 8, height: 8, decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle)),
      );
}

class _Stepper extends StatelessWidget {
  final String label;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;
  const _Stepper({required this.label, this.onMinus, this.onPlus});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton.filledTonal(onPressed: onMinus, icon: const Icon(Icons.remove)),
          SizedBox(
            width: 120,
            child: Text(label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          ),
          IconButton.filledTonal(onPressed: onPlus, icon: const Icon(Icons.add)),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  final String action;
  final VoidCallback onTap;

  const _Banner({required this.icon, required this.color, required this.text, required this.action, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
          TextButton(onPressed: onTap, child: Text(action)),
        ],
      ),
    );
  }
}
