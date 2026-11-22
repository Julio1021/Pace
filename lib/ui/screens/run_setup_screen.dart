import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../domain/calc.dart';
import '../../domain/models.dart';
import '../../services/recorder.dart';
import '../widgets/common.dart';
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
        : (_accuracy! <= 8 ? cs.secondary : (_accuracy! <= 20 ? PaceColors.blue : PaceColors.orange));

    return Scaffold(
      appBar: AppBar(title: const Text('Correr')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
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
          else
            PaceCard(
              child: Row(
                children: [
                  Icon(Icons.gps_fixed, color: qColor),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Sinal de GPS: $quality', style: t.titleSmall?.copyWith(color: qColor)),
                        Text(
                          _accuracy == null
                              ? 'Fique ao ar livre por alguns segundos.'
                              : 'Precisão de ${_accuracy!.round()} m',
                          style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
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
          const SizedBox(height: 24),
          SizedBox(
            height: 64,
            child: FilledButton.icon(
              onPressed: _starting ? null : () => _start(),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
                textStyle: t.titleLarge?.copyWith(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              icon: const Icon(Icons.play_arrow, size: 30),
              label: const Text('Iniciar corrida'),
            ),
          ),
        ],
      ),
    );
  }
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
