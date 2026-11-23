import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../domain/calc.dart';
import '../../domain/coach.dart';
import '../../domain/models.dart';
import '../../domain/stats.dart';
import '../../services/recorder.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/guara.dart';
import '../widgets/pace_ui.dart';
import '../widgets/sky_scene.dart';
import '../widgets/goal_editor.dart';
import '../widgets/voice_every.dart';
import '../../services/weather.dart';
import 'live_run_screen.dart';

/// Preparação da corrida: permissões, sinal de GPS e opções.
class RunSetupScreen extends StatefulWidget {
  /// Se a aba está visível (liga a prévia do GPS só quando necessário).
  final bool active;
  const RunSetupScreen({super.key, this.active = true});

  /// Permite fixar o horário nas prints de teste.
  static DateTime Function() clock = DateTime.now;

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
  final Map<Sport, String> _typeBy = {Sport.run: trainingTypes.first, Sport.bike: bikeTypes.first};
  Sport get _sport => context.read<AppState>().sport;
  String get _type => _typeBy[_sport]!;
  set _type(String v) => _typeBy[_sport] = v;

  LocationPermission? _perm;
  bool _serviceOn = true;
  bool? _batteryOk;
  double? _accuracy;
  StreamSubscription<Position>? _preview;
  bool _visible = false;
  bool _starting = false;
  RunPreset? _applied;
  bool _restored = false;

  // Posições medidas: o bloco do botão fica o mais baixo possível,
  // logo acima da barra de navegação, e os morros acompanham o botão.
  final _topKey = GlobalKey();
  final _btnKey = GlobalKey();
  final _bottomKey = GlobalKey();
  double _gapTop = 22;
  double? _btnCenter;

  /// Espaço reservado para a barra de navegação flutuante (com o botão central).
  static const _navGap = 122.0;

  void _measure() {
    if (!mounted || (_scroll.hasClients && _scroll.offset > 0)) return;
    final top = _topKey.currentContext?.findRenderObject() as RenderBox?;
    final btn = _btnKey.currentContext?.findRenderObject() as RenderBox?;
    final block = _bottomKey.currentContext?.findRenderObject() as RenderBox?;
    if (top == null || btn == null || block == null || !top.hasSize || !btn.hasSize || !block.hasSize) return;
    final screenH = MediaQuery.of(context).size.height;
    final topEnd = top.localToGlobal(Offset(0, top.size.height)).dy;
    final wantTop = math.max(22.0, screenH - _navGap - topEnd - block.size.height);
    final btnCenterNow = btn.localToGlobal(Offset(0, btn.size.height / 2)).dy;
    final center = btnCenterNow + (wantTop - _gapTop);
    if ((wantTop - _gapTop).abs() > 1 || _btnCenter == null || (center - _btnCenter!).abs() > 1) {
      setState(() {
        _gapTop = wantTop;
        _btnCenter = center;
      });
    }
  }
  String? _savedSnap;
  final _scroll = ScrollController();
  final _scrollPos = ValueNotifier<double>(0);
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshStatus();
    _restore();
    _scroll.addListener(() => _scrollPos.value = _scroll.offset);
    // Atualiza o céu a cada minuto (cores mudam aos poucos).
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted && widget.active) setState(() {});
    });
  }

  /// Volta os últimos ajustes usados (tipo, meta e opções da corrida).
  Future<void> _restore() async {
    try {
      final raw = await context.read<AppState>().db.getKv('run_setup');
      if (raw != null && mounted) {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        setState(() {
          final ty = j['type'] as String?;
          if (ty != null && trainingTypes.contains(ty)) _typeBy[Sport.run] = ty;
          final tb = j['type_bike'] as String?;
          if (tb != null && bikeTypes.contains(tb)) _typeBy[Sport.bike] = tb;
          _goal = GoalType.values[((j['goal'] as num?) ?? 0).toInt().clamp(0, GoalType.values.length - 1)];
          _goalKm = ((j['km'] as num?) ?? 5).toDouble();
          _goalMin = ((j['min'] as num?) ?? 30).toInt();
          _autoLap = ((j['lap'] as num?) ?? 0).toDouble();
          _autoPause = j['pause'] != false;
          _voice = j['voice'] != false;
        });
      }
    } catch (_) {}
    _restored = true;
  }

  /// Guarda os ajustes sempre que mudam (exceto quando vieram de um treino do plano).
  void _persist(AppState app) {
    if (!_restored || _applied != null) return;
    final snap = jsonEncode({
      'type': _typeBy[Sport.run],
      'type_bike': _typeBy[Sport.bike],
      'goal': _goal.index,
      'km': _goalKm,
      'min': _goalMin,
      'lap': _autoLap,
      'pause': _autoPause,
      'voice': _voice,
    });
    if (snap == _savedSnap) return;
    _savedSnap = snap;
    app.db.setKv('run_setup', snap);
  }


  String _summary(AppState app) => [
        _type,
        switch (_goal) {
          GoalType.none => 'Sem meta',
          GoalType.distance =>
            'Meta ${_goalKm == _goalKm.roundToDouble() ? _goalKm.toStringAsFixed(0) : _goalKm.toStringAsFixed(1).replaceAll('.', ',')} km',
          GoalType.time => 'Meta $_goalMin min',
        },
        if (!_voice) 'Sem voz' else 'Voz ${app.sport == Sport.bike ? app.bikeVoiceEveryKm : app.voiceEveryKm} km',
      ].join(' · ');

  /// Treino e ajustes num painel que sobe de baixo (duas abas).
  Future<void> _openSettings() async {
    HapticFeedback.selectionClick();
    var tab = 0;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: PaceColors.bgDark,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (sheetCtx) => Theme(
        data: glassTheme,
        child: StatefulBuilder(builder: (context, setSheet) {
          void upd(VoidCallback fn) {
            setState(fn);
            setSheet(() {});
          }

          final app = context.watch<AppState>();
          return ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.86),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.paddingOf(context).bottom),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<int>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: 0,
                        icon: Icon(app.sport == Sport.bike ? Icons.directions_bike_rounded : Icons.directions_run_rounded, size: 18),
                        label: const Text('Treino'),
                      ),
                      ButtonSegment(
                        value: 1,
                        icon: const Icon(Icons.tune_rounded, size: 18),
                        label: Text(app.sport == Sport.bike ? 'Ajustes do pedal' : 'Ajustes da corrida'),
                      ),
                    ],
                    selected: {tab},
                    onSelectionChanged: (v) => setSheet(() => tab = v.first),
                  ),
                  const SizedBox(height: 14),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    alignment: Alignment.topCenter,
                    child: tab == 0
                        ? GlassCard(
            tint: 0.6,
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 0, 4),
                    child: Text('Tipo de treino', style: glassTheme.textTheme.titleSmall),
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                  child: Row(
                    children: [
                      for (final ty in app.sport.types)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: _TypePill(
                            text: ty,
                            selected: ty == _type,
                            onTap: () => upd(() => _type = ty),
                          ),
                        ),
                    ],
                  ),
                ),
                Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Meta', style: glassTheme.textTheme.titleSmall),
                      const SizedBox(height: 8),
                      GoalModePicker<GoalType>(
                        options: const [
                          (GoalType.none, 'Livre', Icons.all_inclusive_rounded),
                          (GoalType.distance, 'Distância', Icons.straighten_rounded),
                          (GoalType.time, 'Tempo', Icons.timer_outlined),
                        ],
                        value: _goal,
                        onChanged: (g) => upd(() => _goal = g),
                      ),
                      if (_goal == GoalType.distance)
                        GoalEditor(byTime: false, value: _goalKm, onChanged: (v) => upd(() => _goalKm = v)),
                      if (_goal == GoalType.time)
                        GoalEditor(byTime: true, value: _goalMin.toDouble(), onChanged: (v) => upd(() => _goalMin = v.round())),
                      if (_goal == GoalType.none)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                              app.sport == Sport.bike
                                  ? 'Sem alvo: pedale o quanto quiser e encerre quando der.'
                                  : 'Sem alvo: corra o quanto quiser e encerre quando der.',
                              style: TextStyle(fontSize: 12.5, color: const Pal(true).muted)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          )
                        : GlassCard(
            tint: 0.6,
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.flag_outlined),
                  title: const Text('Volta automática'),
                  trailing: DropdownButton<double>(
                    value: _autoLap,
                    underline: const SizedBox(),
                    items: [
                      const DropdownMenuItem(value: 0.0, child: Text('Desligada')),
                      const DropdownMenuItem(value: 1000.0, child: Text('A cada 1 km')),
                      const DropdownMenuItem(value: 5000.0, child: Text('A cada 5 km')),
                      if (app.sport == Sport.bike || _autoLap == 10000)
                        const DropdownMenuItem(value: 10000.0, child: Text('A cada 10 km')),
                    ],
                    onChanged: (v) => upd(() => _autoLap = v ?? 0),
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.pause_circle_outline),
                  title: const Text('Pausa automática'),
                  subtitle: const Text('Pausa quando você para (semáforo, por exemplo)'),
                  value: _autoPause,
                  onChanged: (v) => upd(() => _autoPause = v),
                ),
                const Divider(height: 1),
                Builder(builder: (context) {
                  final app = context.watch<AppState>();
                  return ListTile(
                    leading: const Icon(Icons.campaign_outlined),
                    title: const Text('Mensagens de incentivo'),
                    subtitle: Text(app.coachStyle.hint),
                    trailing: DropdownButton<CoachStyle>(
                      value: app.coachStyle,
                      underline: const SizedBox(),
                      items: [
                        for (final s in CoachStyle.values)
                          DropdownMenuItem(value: s, child: Text(s.label.split(' ').first)),
                      ],
                      onChanged: (v) {
                        if (v != null) app.setCoachStyle(v);
                      },
                    ),
                  );
                }),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.record_voice_over_outlined),
                  title: const Text('Avisos por voz'),
                  subtitle: Text(app.sport == Sport.bike ? 'Tempo, distância, velocidade e incentivo' : 'Tempo, distância, pace e incentivo'),
                  value: _voice,
                  onChanged: (v) => upd(() => _voice = v),
                ),
                if (_voice)
                  Builder(builder: (context) {
                    final app = context.watch<AppState>();
                    return ListTile(
                      leading: const Icon(Icons.straighten_rounded),
                      title: const Text('Avisar a cada'),
                      trailing: app.sport == Sport.bike
                          ? VoiceEveryPicker(
                              value: app.bikeVoiceEveryKm,
                              onChanged: app.setBikeVoiceEveryKm,
                              options: VoiceEveryPicker.bikeOptions,
                            )
                          : VoiceEveryPicker(value: app.voiceEveryKm, onChanged: app.setVoiceEveryKm),
                    );
                  }),
              ],
            ),
          ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => Navigator.pop(sheetCtx),
                    child: const Text('Pronto'),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _preview?.cancel();
    _clock?.cancel();
    _scroll.dispose();
    _scrollPos.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshStatus();
      context.read<AppState>().cloudTick();
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
    if (!mounted) return;
    if (!await showStartCountdown(context)) return;
    if (!mounted) return;
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
        sport: _sport,
        coachStyle: context.read<AppState>().coachStyle,
        voiceEveryKm: _sport == Sport.bike ? context.read<AppState>().bikeVoiceEveryKm : context.read<AppState>().voiceEveryKm,
      );
      context.read<AppState>().clearPreset();
      _applied = null;
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
    if (rec.isActive) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: EmptyState(
              icon: Icons.directions_run,
              art: const Guara(pose: GuaraPose.run, size: 130),
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

    final now = RunSetupScreen.clock();
    final app = context.watch<AppState>();
    var lat = SkyInfo.defaultLat, lon = SkyInfo.defaultLon;
    for (final a in app.activities) {
      final first = a.preview.split(';').first.split(',');
      if (first.length == 2) {
        final la = double.tryParse(first[0]), lo = double.tryParse(first[1]);
        if (la != null && lo != null) {
          lat = la;
          lon = lo;
          break;
        }
      }
    }
    _persist(app);
    final w = app.weather;
    final sky = SkyInfo.at(now, lat: lat, lon: lon).withWeather(w);
    // Previsão do tempo (a cada 30 min, só com a tela visível).
    if (widget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.read<AppState>().refreshWeather(lat, lon);
      });
    }
    // Treino escolhido num plano: preenche tipo e meta uma vez.
    final preset = app.pendingPreset;
    if (preset != null && !identical(preset, _applied)) {
      _applied = preset;
      // Planos de treino são de corrida.
      if (app.sport != Sport.run) {
        WidgetsBinding.instance.addPostFrameCallback((_) => app.setSport(Sport.run));
      }
      _typeBy[Sport.run] = trainingTypes.contains(preset.type) ? preset.type : trainingTypes.first;
      if (preset.byTime) {
        _goal = GoalType.time;
        _goalMin = preset.value.round();
      } else {
        _goal = GoalType.distance;
        _goalKm = preset.value;
      }
    }
    final onSky = sky.onSky;
    final base = Theme.of(context);
    final mq = MediaQuery.of(context);
    // Os morros ficam logo abaixo do botão Iniciar.
    // Os morros ficam um pouco acima do centro do botão (ele "pousa" na paisagem).
    final horizon = (_btnCenter ?? mq.padding.top + 264) - 4;
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    return Scaffold(
      backgroundColor: sky.look.ground,
      body: Stack(
        children: [
          Positioned.fill(
            child: SkyScene(info: sky, lat: lat, scroll: _scrollPos, horizon: horizon, animate: widget.active),
          ),
          SafeArea(
            bottom: false,
            child: Theme(
              data: base.copyWith(
                colorScheme: base.colorScheme.copyWith(onSurface: sky.onGround),
                textTheme: base.textTheme.apply(bodyColor: sky.onGround, displayColor: sky.onGround),
              ),
              child: ListView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
        children: [
          Appear(
            child: Row(
              children: [
                Text(app.sport.verb, style: numStyle(28, color: onSky)),
                const SizedBox(width: 10),
                // Sinal do GPS: só um pontinho colorido (toque para ver a precisão).
                if (_hasPermission && _serviceOn)
                  Tooltip(
                    triggerMode: TooltipTriggerMode.tap,
                    showDuration: const Duration(seconds: 3),
                    message: _accuracy == null ? 'Procurando GPS…' : 'GPS ${quality.toLowerCase()} · precisão de ${_accuracy!.round()} m',
                    child: Semantics(
                      label: _accuracy == null ? 'Procurando GPS' : 'GPS ${quality.toLowerCase()}',
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.55),
                        ),
                        child: _Blink(color: qColor),
                      ),
                    ),
                  ),
                const Spacer(),
                _SportSwitch(
                  value: app.sport,
                  onChanged: _applied != null && app.sport == Sport.run
                      ? null
                      : (s) {
                          HapticFeedback.selectionClick();
                          app.setSport(s);
                        },
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Appear(
            key: _topKey,
            delayMs: 60,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Text('${Fmt.weekdayDate(now.toUtc()).split(',').first} · ${sky.label}',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: onSky.withValues(alpha: 0.75))),
                    if (w != null) _WeatherChip(w: w),
                  ],
                ),
                const SizedBox(height: 2),
                SizedBox(
                  width: 270,
                  child: Text(sportPhrase(sky.phrase, app.sport), style: numStyle(30, color: onSky, height: 1.1)),
                ),
              ],
            ),
          ),
          SizedBox(height: _gapTop),
          Column(
            key: _bottomKey,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
          if (!_hasPermission)
            _Banner(
              icon: Icons.location_off,
              color: PaceColors.orange,
              text: 'Permita a localização para gravar seus treinos com GPS.',
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
          if (_applied != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: PaceColors.mint.withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.event_note_rounded, color: PaceColors.mintDark),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Treino do plano · ${_applied!.label}',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: PaceColors.mintDark)),
                          Text(
                            context.read<AppState>().plan?.plan?.sessions[_applied!.sessionIndex].detail ?? '',
                            style: const TextStyle(fontSize: 13, color: PaceColors.ink, height: 1.3),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Correr sem o plano',
                      onPressed: () {
                        context.read<AppState>().clearPreset();
                        setState(() {
                          _applied = null;
                          _goal = GoalType.none;
                          _typeBy[Sport.run] = trainingTypes.first;
                        });
                      },
                      icon: const Icon(Icons.close_rounded, color: PaceColors.muted),
                    ),
                  ],
                ),
              ),
            ),
          Appear(
            delayMs: 120,
            child: Center(
              // Largura extra dos dois lados para a engrenagem caber (e receber o toque).
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const SizedBox(width: 290, height: 176),
                  Builder(builder: (context) {
                if (app.sport == Sport.bike) {
                  final wk = PeriodStats.of(Periods.between(app.rides, Periods.weekStart(now), now.add(const Duration(days: 1)))).distanceM;
                  final caption = wk <= 0 ? 'Bora pedalar?' : '${Fmt.km(wk, decimals: 1)} km\npedalados na semana';
                  return _StartButton(key: _btnKey, onTap: _starting ? null : () => _start(), progress: 0, caption: caption, bike: true);
                }
                final goal = app.profile.weeklyGoalKm;
                final km = app.weekStats(now).distanceM / 1000;
                final prog = goal > 0 ? km / goal : 0.0;
                final caption = goal <= 0
                    ? 'Bora correr?'
                    : prog >= 1
                        ? 'Meta da semana\nbatida!'
                        : '${Fmt.km(km * 1000, decimals: 1)} de '
                            '${goal == goal.roundToDouble() ? goal.toInt() : Fmt.km(goal * 1000, decimals: 1)} km\nna semana';
                return _StartButton(key: _btnKey, onTap: _starting ? null : () => _start(), progress: prog, caption: caption);
              }),
                  // Engrenagem: abre treino e ajustes.
                  Positioned(
                    right: 0,
                    bottom: 26,
                    child: IconButton(
                      key: const ValueKey('run-settings'),
                      tooltip: 'Treino e ajustes',
                      onPressed: _openSettings,
                      icon: Icon(Icons.settings_rounded, size: 30, color: onSky.withValues(alpha: 0.92), shadows: const [
                        Shadow(color: Color(0x55000000), blurRadius: 8),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 2),
          Center(
            child: _SummaryPill(text: _summary(app), onTap: _openSettings),
          ),
            ],
          ),
          SizedBox(height: _navGap),
        ],
      ),
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

  /// Progresso da meta da semana (0 a 1) e o texto embaixo de "INICIAR".
  final double progress;
  final String caption;
  final bool bike;
  const _StartButton({super.key, required this.onTap, required this.progress, required this.caption, this.bike = false});

  @override
  State<_StartButton> createState() => _StartButtonState();
}

class _StartButtonState extends State<_StartButton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));
  bool _down = false;

  static const orb = 136.0;
  static const ring = 152.0;
  static const box = 176.0;

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
    final done = widget.progress >= 1;
    final orbChild = Container(
      width: orb,
      height: orb,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xF02B3340), Color(0xF5121720)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        boxShadow: [
          BoxShadow(color: PaceColors.mintBright.withValues(alpha: 0.28), blurRadius: 26, offset: const Offset(0, 8)),
          const BoxShadow(color: Color(0x330F172A), blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: Stack(
        children: [
          // Reflexo do vidro: um brilho suave no alto, à esquerda.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: const Alignment(-0.45, -0.6),
                  radius: 0.75,
                  colors: [Colors.white.withValues(alpha: 0.13), Colors.white.withValues(alpha: 0)],
                ),
              ),
            ),
          ),
          // Fio de luz na borda de cima.
          Positioned.fill(child: CustomPaint(painter: _RimPainter())),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.play_arrow_rounded, size: 44, color: PaceColors.mintBright),
                Text('INICIAR', style: numStyle(16, color: Colors.white).copyWith(letterSpacing: 2)),
                const SizedBox(height: 3),
                SizedBox(
                  width: 96,
                  child: Text(
                    widget.caption,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: TextStyle(
                      fontSize: 10,
                      height: 1.25,
                      color: Colors.white.withValues(alpha: 0.75),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return Semantics(
      button: true,
      label: '${widget.bike ? 'Iniciar pedal' : 'Iniciar corrida'}. ${widget.caption.replaceAll('\n', ' ')}',
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? 0.94 : 1,
          duration: const Duration(milliseconds: 120),
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, child) {
              final t = _c.value;
              return SizedBox(
                width: box,
                height: box,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Onda suave saindo do anel.
                    Container(
                      width: ring + 24 * t,
                      height: ring + 24 * t,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: PaceColors.mintBright.withValues(alpha: 0.45 * (1 - t)),
                          width: 2,
                        ),
                      ),
                    ),
                    CustomPaint(
                      size: const Size(ring, ring),
                      painter: _GoalRingPainter(widget.progress.clamp(0.0, 1.0), done ? 0.6 + 0.4 * (1 - t) : 0),
                    ),
                    child!,
                  ],
                ),
              );
            },
            child: orbChild,
          ),
        ),
      ),
    );
  }
}

class _RimPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(1.5);
    canvas.drawArc(
      rect,
      math.pi * 1.1,
      math.pi * 0.8,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: math.pi * 1.1,
          endAngle: math.pi * 1.9,
          colors: [Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: 0.45), Colors.white.withValues(alpha: 0)],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_RimPainter o) => false;
}

/// Anel da meta semanal em volta do botão.
class _GoalRingPainter extends CustomPainter {
  final double progress;
  final double glow;
  _GoalRingPainter(this.progress, this.glow);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 4;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = Colors.white.withValues(alpha: 0.32),
    );
    if (progress <= 0) return;
    final rect = Rect.fromCircle(center: c, radius: r);
    if (glow > 0) {
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 14
          ..color = PaceColors.mintBright.withValues(alpha: 0.25 * glow)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..shader = const SweepGradient(
          startAngle: -math.pi / 2,
          endAngle: 3 * math.pi / 2,
          colors: [Color(0xFF14B887), PaceColors.mintBright, Color(0xFF14B887)],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_GoalRingPainter o) => o.progress != progress || o.glow != glow;
}

/// Contagem 3-2-1 com o Guará correndo; um toque cancela. Devolve true se completou.
Future<bool> showStartCountdown(BuildContext context) async {
  final r = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, a1, a2) => const _Countdown(),
    transitionBuilder: (ctx, a, a2, child) => FadeTransition(opacity: a, child: child),
  );
  return r ?? false;
}

class _Countdown extends StatefulWidget {
  const _Countdown();

  @override
  State<_Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<_Countdown> {
  int _n = 3;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    HapticFeedback.mediumImpact();
    _t = Timer.periodic(const Duration(milliseconds: 850), (_) {
      if (!mounted) return;
      if (_n > 1) {
        setState(() => _n--);
        HapticFeedback.mediumImpact();
      } else if (_n == 1) {
        setState(() => _n = 0);
        HapticFeedback.heavyImpact();
      } else {
        _t?.cancel();
        Navigator.of(context).pop(true);
      }
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final motion = motionOn(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        _t?.cancel();
        Navigator.of(context).pop(false);
      },
      child: Material(
        color: const Color(0xD90B1220),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 3),
              AnimatedSwitcher(
                duration: Duration(milliseconds: motion ? 320 : 0),
                transitionBuilder: (c, a) => ScaleTransition(
                  scale: Tween(begin: 1.6, end: 1.0).animate(CurvedAnimation(parent: a, curve: Curves.easeOutBack)),
                  child: FadeTransition(opacity: a, child: c),
                ),
                child: Text(
                  _n == 0 ? 'Bora!' : '$_n',
                  key: ValueKey(_n),
                  style: numStyle(_n == 0 ? 64 : 120, color: _n == 0 ? PaceColors.mintBright : Colors.white),
                ),
              ),
              const SizedBox(height: 24),
              const Guara(pose: GuaraPose.run, size: 120),
              const Spacer(flex: 2),
              Text('Toque para cancelar', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 14)),
              const SizedBox(height: 36),
            ],
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

/// Pílula do tipo de treino.
class _TypePill extends StatelessWidget {
  final String text;
  final bool selected;
  final VoidCallback onTap;
  const _TypePill({required this.text, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? Colors.white : Colors.white.withValues(alpha: 0.14)),
        ),
        child: Text(text,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13.5,
              color: selected ? PaceColors.ink : Colors.white.withValues(alpha: 0.85),
            )),
      ),
    );
  }
}

/// Clima agora, ao lado do dia da semana.
class _WeatherChip extends StatelessWidget {
  final WeatherNow w;
  const _WeatherChip({required this.w});

  IconData get _icon => switch (w.kind) {
        WeatherKind.clear => w.hot ? Icons.wb_sunny_rounded : Icons.wb_sunny_outlined,
        WeatherKind.partly => Icons.wb_cloudy_outlined,
        WeatherKind.cloudy => Icons.cloud_rounded,
        WeatherKind.fog => Icons.foggy,
        WeatherKind.drizzle => Icons.grain_rounded,
        WeatherKind.rain => Icons.umbrella_rounded,
        WeatherKind.storm => Icons.thunderstorm_rounded,
        WeatherKind.snow => Icons.ac_unit_rounded,
      };

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Tempo agora: ${w.label}, ${w.tempC.round()} graus',
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icon, size: 15, color: PaceColors.mintDark),
            const SizedBox(width: 4),
            Text('${w.tempC.round()}° · ${w.label}${w.windy && !w.wet ? ' · vento' : ''}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: PaceColors.ink)),
          ],
        ),
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
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        boxShadow: const [BoxShadow(color: Color(0x220F172A), blurRadius: 14, offset: Offset(0, 6))],
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(color: PaceColors.ink, fontSize: 14, height: 1.3))),
          TextButton(
            onPressed: onTap,
            child: Text(action, style: const TextStyle(color: PaceColors.mintDark, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

/// Adapta a frase do céu para o pedal ("correr" vira "pedalar").
String sportPhrase(String s, Sport sport) {
  if (sport == Sport.run) return s;
  const map = {
    'Corrida noturna?': 'Pedal noturno?',
    'Corra com': 'Pedale com',
    'correndo': 'pedalando',
    'correr': 'pedalar',
    'Use roupa refletiva.': 'Use luz e refletivo.',
  };
  var out = s;
  map.forEach((k, v) => out = out.replaceAll(k, v));
  return out;
}

/// Seletor Corrida | Pedal (vidro sobre o céu).
class _SportSwitch extends StatelessWidget {
  final Sport value;
  final ValueChanged<Sport>? onChanged;
  const _SportSwitch({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget item(Sport s, IconData icon) {
      final sel = s == value;
      return Semantics(
        selected: sel,
        button: true,
        label: s.label,
        child: GestureDetector(
          onTap: onChanged == null || sel ? null : () => onChanged!(s),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: sel ? PaceColors.bgDark.withValues(alpha: 0.82) : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 17, color: sel ? PaceColors.mintBright : PaceColors.ink.withValues(alpha: 0.7)),
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  child: sel
                      ? Padding(
                          padding: const EdgeInsets.only(left: 5),
                          child: Text(s.label,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white)),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Opacity(
      opacity: onChanged == null ? 0.6 : 1,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.62),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            item(Sport.run, Icons.directions_run_rounded),
            item(Sport.bike, Icons.directions_bike_rounded),
          ],
        ),
      ),
    );
  }
}

/// Resumo do treino escolhido (toque abre a engrenagem).
class _SummaryPill extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  const _SummaryPill({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Treino: $text. Toque para ajustar.',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 330),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: PaceColors.bgDark.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
