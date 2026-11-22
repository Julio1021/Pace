import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';

import '../core/format.dart';
import '../data/database.dart';
import '../domain/calc.dart';
import '../domain/models.dart';

enum GoalType { none, distance, time }

/// Opções escolhidas antes de iniciar a corrida.
class RunConfig {
  final GoalType goalType;
  final double goalValue; // metros (distância) ou segundos (tempo)
  final double autoLapM; // 0 = desligada
  final bool autoPause;
  final bool voice;
  final String type;

  const RunConfig({
    this.goalType = GoalType.none,
    this.goalValue = 0,
    this.autoLapM = 0,
    this.autoPause = true,
    this.voice = true,
    this.type = 'Corrida livre',
  });
}

enum RecState { idle, running, paused, finished }

/// Grava a corrida: GPS contínuo num serviço em primeiro plano (continua com a tela
/// bloqueada), filtro de pontos, pausa automática, parciais, voltas e avisos por voz.
/// Cada ponto é salvo no banco em lotes de até 5 s; se o app fechar, a corrida pode ser retomada.
class Recorder extends ChangeNotifier {
  final PaceDatabase Function() _db;
  final double Function() _weightKg;

  Recorder({required PaceDatabase Function() db, required double Function() weightKg})
      : _db = db,
        _weightKg = weightKg;

  RecState state = RecState.idle;
  RunConfig config = const RunConfig();
  int? activityId;
  DateTime? startTime;

  final points = <TrackPoint>[];
  final splits = <Split>[];
  final laps = <Lap>[];

  double distance = 0;
  double moving = 0; // segundos em movimento
  double? accuracy;
  double? speed;
  bool autoPaused = false;
  String? gpsWarning;

  StreamSubscription<Position>? _sub;
  Timer? _ticker;
  DateTime? _clock;
  TrackPoint? _lastAccepted;
  bool _segmentBreak = false;
  double _prevMov = 0;
  double _prevDist = 0;
  double _nextKm = 1000;
  double _lastSplitMov = 0;
  double _nextLap = 0;
  double _lapStartMov = 0;
  double _lapStartDist = 0;
  bool _goalAnnounced = false;
  final _pending = <TrackPoint>[];
  int _savedCount = 0;
  DateTime _lastFlush = DateTime.now();
  final _autoPause = AutoPause();
  final _paceWindow = PaceWindow();
  FlutterTts? _tts;
  bool _busy = false;

  bool get isActive => state == RecState.running || state == RecState.paused;
  bool get manuallyPaused => state == RecState.paused;

  double get elapsed => startTime == null ? 0 : DateTime.now().toUtc().difference(startTime!).inMilliseconds / 1000;
  double? get currentPace => (manuallyPaused || autoPaused) ? null : _paceWindow.current;
  double? get avgPace => Calc.pace(moving, distance);
  double? get avgSpeed => moving > 0 ? distance / moving : null;
  double get calories => Calc.calories(_weightKg(), distance);
  double get lapDistance => distance - _lapStartDist;
  double get lapTime => moving - _lapStartMov;

  // ---------------- Ciclo de vida ----------------

  static AndroidSettings locationSettings() => AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 1),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'PACE — corrida em andamento',
          notificationText: 'Gravando seu percurso. Toque para voltar ao app.',
          notificationChannelName: 'Corrida em andamento',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );

  Future<void> start(RunConfig cfg) async {
    if (isActive) return;
    _reset();
    config = cfg;
    final now = DateTime.now().toUtc();
    startTime = now;
    activityId = await _db().insertActivity(Activity(
      start: now,
      type: cfg.type,
      source: ActivitySource.recorded,
      status: ActivityStatus.inProgress,
    ));
    state = RecState.running;
    _clock = DateTime.now();
    _nextLap = cfg.autoLapM;
    await _initTts();
    _listen();
    _say('Corrida iniciada.');
    notifyListeners();
  }

  /// Retoma uma corrida interrompida (app fechado ou celular reiniciado).
  Future<void> resumeInterrupted(Activity a) async {
    if (isActive) return;
    _reset();
    final db = _db();
    final pts = await db.getPoints(a.id!);
    activityId = a.id;
    startTime = a.start;
    config = RunConfig(type: a.type);
    points.addAll(pts);
    _savedCount = pts.length;
    laps.addAll(await db.getLaps(a.id!));
    if (pts.isNotEmpty) {
      final last = pts.last;
      distance = last.dist;
      moving = last.mov;
      _lastAccepted = last;
      _prevDist = distance;
      _prevMov = moving;
    }
    splits.addAll(Calc.splits(pts).where((s) => s.distM >= 999.9));
    _nextKm = (splits.length + 1) * 1000.0;
    _lastSplitMov = splits.fold(0.0, (t, s) => t + s.sec);
    if (laps.isNotEmpty) {
      _lapStartDist = laps.fold(0.0, (t, l) => t + l.distM);
      _lapStartMov = laps.fold(0.0, (t, l) => t + l.sec);
    }
    _segmentBreak = true; // não soma a distância do intervalo em que o app esteve fechado
    state = RecState.running;
    _clock = DateTime.now();
    await _initTts();
    _listen();
    _say('Corrida retomada.');
    notifyListeners();
  }

  void pause() {
    if (state != RecState.running) return;
    _advanceClock(DateTime.now());
    state = RecState.paused;
    _paceWindow.clear();
    HapticFeedback.mediumImpact();
    _say('Corrida pausada.');
    notifyListeners();
  }

  void resume() {
    if (state != RecState.paused) return;
    _clock = DateTime.now();
    state = RecState.running;
    _segmentBreak = true;
    _autoPause.reset();
    autoPaused = false;
    HapticFeedback.mediumImpact();
    _say('Retomando.');
    notifyListeners();
  }

  void markLap() {
    if (!isActive) return;
    _closeLap(manual: true);
    HapticFeedback.heavyImpact();
    final l = laps.last;
    _say('Volta ${l.index}. ${_spokenDuration(l.sec)}.');
    notifyListeners();
  }

  /// Encerra e salva. Devolve o id da atividade.
  Future<int?> finish() async {
    if (!isActive || _busy) return activityId;
    _busy = true;
    try {
      if (state == RecState.running) _advanceClock(DateTime.now());
      await _stopStream();
      await _flush();
      final id = activityId!;
      await finalizeActivity(_db(), id, weightKg: _weightKg(), extraLaps: laps, endTime: DateTime.now().toUtc());
      state = RecState.finished;
      _say('Corrida encerrada. ${Fmt.km(distance).replaceAll(',', ' vírgula ')} quilômetros.');
      notifyListeners();
      return id;
    } finally {
      _busy = false;
    }
  }

  Future<void> discard() async {
    final id = activityId;
    await _stopStream();
    if (id != null) await _db().deleteActivity(id);
    _reset();
    state = RecState.idle;
    notifyListeners();
  }

  /// Volta ao estado inicial depois de ver o resultado.
  void clear() {
    if (isActive) return;
    _reset();
    state = RecState.idle;
    notifyListeners();
  }

  // ---------------- Finalização (também usada para "salvar como está") ----------------

  static Future<void> finalizeActivity(
    PaceDatabase db,
    int id, {
    required double weightKg,
    List<Lap>? extraLaps,
    DateTime? endTime,
  }) async {
    final a = await db.getActivity(id);
    if (a == null) return;
    final pts = await db.getPoints(id);
    final last = pts.isEmpty ? null : pts.last;
    final dist = last?.dist ?? 0;
    final mov = last?.mov ?? 0;
    final splits = Calc.splits(pts);
    final elev = Calc.elevation(pts.where((p) => !p.paused).map((p) => p.alt).toList());
    final hr = Calc.heartRate(pts);
    final end = endTime ?? last?.time ?? a.start;
    final laps = extraLaps ?? await db.getLaps(id);
    await db.updateActivity(a.copyWith(
      end: end,
      movingSec: mov.round(),
      elapsedSec: end.difference(a.start).inSeconds,
      distanceM: dist,
      calories: Calc.calories(weightKg, dist),
      elevGain: elev.gain,
      elevLoss: elev.loss,
      avgHr: hr.avg,
      maxHr: hr.max,
      avgCad: Calc.avgCadence(pts),
      bestKmSec: Calc.bestKm(splits),
      lapCount: laps.length,
      preview: Calc.preview(pts),
      status: ActivityStatus.done,
    ));
    await db.replaceSplitsAndLaps(id, splits, laps);
  }

  // ---------------- GPS ----------------

  void _listen() {
    _sub?.cancel();
    _sub = Geolocator.getPositionStream(locationSettings: locationSettings()).listen(
      _onPosition,
      onError: (Object e) {
        gpsWarning = 'Sinal de GPS indisponível. Verifique se a localização está ligada.';
        notifyListeners();
      },
    );
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state == RecState.running) _advanceClock(DateTime.now());
      if (_pending.isNotEmpty && DateTime.now().difference(_lastFlush).inSeconds >= 5) _flush();
      notifyListeners();
    });
  }

  Future<void> _stopStream() async {
    _ticker?.cancel();
    _ticker = null;
    await _sub?.cancel();
    _sub = null;
  }

  void _advanceClock(DateTime now) {
    final c = _clock;
    _clock = now;
    if (c == null || state != RecState.running || autoPaused) return;
    final dt = now.difference(c).inMilliseconds / 1000.0;
    if (dt > 0 && dt < 3600) moving += dt;
  }

  void _onPosition(Position p) {
    if (state != RecState.running) {
      accuracy = p.accuracy;
      return;
    }
    final now = DateTime.now();
    final t = p.timestamp.toUtc();
    accuracy = p.accuracy;
    gpsWarning = p.accuracy > GpsFilter.maxAccuracyM ? 'Sinal de GPS fraco' : null;

    // Velocidade: a do GPS quando disponível; senão, calculada em relação ao último ponto.
    var v = p.speed;
    final last = _lastAccepted;
    if ((v <= 0 || !v.isFinite) && last != null) {
      final dt = t.difference(last.time).inMilliseconds / 1000.0;
      if (dt > 0) v = Calc.haversine(last.lat, last.lon, p.latitude, p.longitude) / dt;
    }
    speed = v;

    // Pausa automática decide se este intervalo conta como tempo em movimento.
    if (config.autoPause) {
      final was = autoPaused;
      final nowPaused = _autoPause.update(t, v);
      if (nowPaused != was) {
        if (nowPaused) {
          _advanceClock(now);
          autoPaused = true;
          _paceWindow.clear();
          _say('Pausa automática.');
        } else {
          _clock = now;
          autoPaused = false;
          _say('Retomando.');
        }
      }
    }
    _advanceClock(now);

    final verdict = GpsFilter.check(
      accuracy: p.accuracy,
      lat: p.latitude,
      lon: p.longitude,
      time: t,
      lastAccepted: _segmentBreak ? null : last,
    );
    if (verdict != GpsVerdict.accept) {
      notifyListeners();
      return;
    }

    var d = 0.0;
    if (last != null && !_segmentBreak && !autoPaused) {
      d = Calc.haversine(last.lat, last.lon, p.latitude, p.longitude);
    }
    _segmentBreak = false;
    distance += d;
    final point = TrackPoint(
      time: t,
      lat: p.latitude,
      lon: p.longitude,
      alt: p.altitude == 0 ? null : p.altitude,
      accuracy: p.accuracy,
      speed: v,
      dist: distance,
      mov: moving,
      paused: autoPaused,
    );
    points.add(point);
    _pending.add(point);
    _lastAccepted = point;

    if (!autoPaused) {
      _paceWindow.add(moving, distance);
      _checkSplits();
      _checkAutoLap();
      _checkGoal();
    }
    _prevMov = moving;
    _prevDist = distance;

    if (_pending.length >= 5 || now.difference(_lastFlush).inSeconds >= 5) _flush();
    notifyListeners();
  }

  double _interpMov(double target) {
    final dd = distance - _prevDist;
    if (dd <= 0) return moving;
    final f = ((target - _prevDist) / dd).clamp(0.0, 1.0);
    return _prevMov + (moving - _prevMov) * f;
  }

  void _checkSplits() {
    while (distance >= _nextKm) {
      final cross = _interpMov(_nextKm);
      final sec = cross - _lastSplitMov;
      splits.add(Split(km: splits.length + 1, distM: 1000, sec: sec));
      _lastSplitMov = cross;
      _nextKm += 1000;
      HapticFeedback.heavyImpact();
      if (config.voice) {
        final km = splits.length;
        _say('$km ${km == 1 ? 'quilômetro' : 'quilômetros'}. '
            'Tempo ${_spokenDuration(moving)}. '
            'Último quilômetro em ${_spokenDuration(sec)}. '
            'Pace médio ${_spokenDuration(avgPace ?? 0)}.');
      }
    }
  }

  void _checkAutoLap() {
    if (config.autoLapM <= 0) return;
    while (distance >= _nextLap) {
      final cross = _interpMov(_nextLap);
      laps.add(Lap(index: laps.length + 1, distM: _nextLap - _lapStartDist, sec: cross - _lapStartMov, manual: false));
      _lapStartDist = _nextLap;
      _lapStartMov = cross;
      _nextLap += config.autoLapM;
    }
  }

  void _closeLap({required bool manual}) {
    laps.add(Lap(index: laps.length + 1, distM: distance - _lapStartDist, sec: moving - _lapStartMov, manual: manual));
    _lapStartDist = distance;
    _lapStartMov = moving;
    if (config.autoLapM > 0) _nextLap = distance + config.autoLapM;
    final id = activityId;
    if (id != null) {
      _db().replaceSplitsAndLaps(id, const [], laps);
    }
  }

  void _checkGoal() {
    if (_goalAnnounced || config.goalType == GoalType.none) return;
    final reached = switch (config.goalType) {
      GoalType.distance => distance >= config.goalValue,
      GoalType.time => moving >= config.goalValue,
      GoalType.none => false,
    };
    if (reached) {
      _goalAnnounced = true;
      HapticFeedback.heavyImpact();
      _say('Meta atingida! Parabéns.', force: true);
    }
  }

  /// Progresso da meta (0 a 1), ou nulo sem meta.
  double? get goalProgress => switch (config.goalType) {
        GoalType.none => null,
        GoalType.distance => config.goalValue > 0 ? (distance / config.goalValue).clamp(0.0, 1.0) : null,
        GoalType.time => config.goalValue > 0 ? (moving / config.goalValue).clamp(0.0, 1.0) : null,
      };

  Future<void> _flush() async {
    final id = activityId;
    if (id == null || _pending.isEmpty) return;
    final batch = List<TrackPoint>.of(_pending);
    _pending.clear();
    _lastFlush = DateTime.now();
    final first = _savedCount;
    _savedCount += batch.length;
    try {
      await _db().appendPoints(id, first, batch);
    } catch (_) {
      // Mantém os pontos para tentar de novo no próximo lote.
      _pending.insertAll(0, batch);
      _savedCount = first;
    }
  }

  // ---------------- Voz ----------------

  Future<void> _initTts() async {
    if (_tts != null) return;
    try {
      final tts = FlutterTts();
      await tts.setLanguage('pt-BR');
      await tts.setSpeechRate(0.5);
      _tts = tts;
    } catch (_) {
      _tts = null;
    }
  }

  void _say(String text, {bool force = false}) {
    if (!config.voice && !force) return;
    final tts = _tts;
    if (tts == null) return;
    tts.speak(text).catchError((Object _) => null);
  }

  static String _spokenDuration(double seconds) {
    final s = seconds.round();
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    final parts = <String>[];
    if (h > 0) parts.add('$h ${h == 1 ? 'hora' : 'horas'}');
    if (m > 0) parts.add('$m ${m == 1 ? 'minuto' : 'minutos'}');
    if (sec > 0 || parts.isEmpty) parts.add('$sec ${sec == 1 ? 'segundo' : 'segundos'}');
    if (parts.length == 1) return parts.first;
    return '${parts.sublist(0, parts.length - 1).join(', ')} e ${parts.last}';
  }

  void _reset() {
    _sub?.cancel();
    _sub = null;
    _ticker?.cancel();
    _ticker = null;
    activityId = null;
    startTime = null;
    points.clear();
    splits.clear();
    laps.clear();
    distance = 0;
    moving = 0;
    accuracy = null;
    speed = null;
    autoPaused = false;
    gpsWarning = null;
    _clock = null;
    _lastAccepted = null;
    _segmentBreak = false;
    _prevMov = 0;
    _prevDist = 0;
    _nextKm = 1000;
    _lastSplitMov = 0;
    _nextLap = 0;
    _lapStartMov = 0;
    _lapStartDist = 0;
    _goalAnnounced = false;
    _pending.clear();
    _savedCount = 0;
    _autoPause.reset();
    _paceWindow.clear();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ticker?.cancel();
    super.dispose();
  }
}
