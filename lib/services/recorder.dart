import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/format.dart';
import 'run_notification.dart';
import 'speech.dart';
import 'voice.dart';
import 'package:geolocator/geolocator.dart';

import '../data/database.dart';
import '../domain/calc.dart';
import '../domain/coach.dart';
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
  final CoachStyle coachStyle;

  /// Avisos de voz a cada N km.
  final int voiceEveryKm;

  /// Corrida ou pedal.
  final Sport sport;

  const RunConfig({
    this.goalType = GoalType.none,
    this.goalValue = 0,
    this.autoLapM = 0,
    this.autoPause = true,
    this.voice = true,
    this.type = 'Corrida livre',
    this.coachStyle = CoachStyle.energetic,
    this.voiceEveryKm = 1,
    this.sport = Sport.run,
  });
}

enum RecState { idle, running, paused, finished }

/// Grava a corrida: GPS contínuo num serviço em primeiro plano (continua com a tela
/// bloqueada), filtro de pontos, pausa automática, parciais, voltas e avisos por voz.
/// Cada ponto é salvo no banco em lotes de até 5 s; se o app fechar, a corrida pode ser retomada.
class Recorder extends ChangeNotifier {
  final PaceDatabase Function() _db;
  final double Function() _weightKg;
  final CoachStyle Function() _defaultStyle;

  Recorder({
    required PaceDatabase Function() db,
    required double Function() weightKg,
    CoachStyle Function()? coachStyle,
  })  : _db = db,
        _weightKg = weightKg,
        _defaultStyle = coachStyle ?? (() => CoachStyle.energetic) {
    RunNotification.onAction = (a) {
      if (a != 'toggle') return;
      if (state == RecState.running) {
        pause();
      } else if (state == RecState.paused) {
        resume();
      }
    };
  }

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

  /// Última frase de incentivo (mostrada também na tela, por alguns segundos).
  String? coachMessage;
  DateTime? coachMessageAt;
  Coach _coach = Coach(style: CoachStyle.off);

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
  GpsSmoother _smoother = GpsSmoother();
  DateTime? _lastRawTime;
  final _speaker = Speaker();
  bool _busy = false;

  bool get isActive => state == RecState.running || state == RecState.paused;
  bool get manuallyPaused => state == RecState.paused;

  double get elapsed => startTime == null ? 0 : DateTime.now().toUtc().difference(startTime!).inMilliseconds / 1000;
  double? get currentPace => (manuallyPaused || autoPaused) ? null : _paceWindow.current;
  double? get avgPace => Calc.pace(moving, distance);

  bool get isBike => config.sport == Sport.bike;


  /// Velocidade atual em km/h (janela de 30 s), nula parado.
  double? get currentKmh {
    final p = currentPace;
    return p == null || p <= 0 ? null : 3600 / p;
  }

  double? get avgKmh => moving > 0 && distance >= 10 ? distance / moving * 3.6 : null;
  double? get avgSpeed => moving > 0 ? distance / moving : null;
  double get calories => Calc.caloriesFor(config.sport, _weightKg(), distance, moving);
  /// Maior velocidade (média móvel de 30 s) em km/h.
  double maxKmh = 0;

  double get lapDistance => distance - _lapStartDist;
  double get lapTime => moving - _lapStartMov;

  // ---------------- Ciclo de vida ----------------

  static AndroidSettings locationSettings() => AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 1),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'PACE — treino em andamento',
          notificationText: 'Gravando seu percurso. Toque para voltar ao app.',
          notificationChannelName: 'Treino em andamento',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );

  Future<void> start(RunConfig cfg) async {
    if (isActive) return;
    _reset();
    config = cfg;
    _applySport();
    final now = DateTime.now().toUtc();
    startTime = now;
    activityId = await _db().insertActivity(Activity(
      start: now,
      type: cfg.type,
      sport: cfg.sport,
      source: ActivitySource.recorded,
      status: ActivityStatus.inProgress,
    ));
    state = RecState.running;
    _clock = DateTime.now();
    _nextLap = cfg.autoLapM;
    _coach = Coach(style: cfg.coachStyle, hasGoal: cfg.goalType != GoalType.none, isRace: cfg.type == 'Prova');
    await _initTts();
    _listen();
    _notify(force: true);
    final hi = _coach.onStart();
    _say([isBike ? 'Pedal iniciado.' : 'Corrida iniciada.', hi]);
    _showCoach(hi);
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
    config = RunConfig(
      type: a.type,
      sport: a.sport,
      coachStyle: _defaultStyle(),
      voiceEveryKm: a.isBike ? 5 : 1,
    );
    _applySport();
    _coach = Coach(style: config.coachStyle);
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
    _notify(force: true);
    _say([isBike ? 'Pedal retomado.' : 'Corrida retomada.']);
    notifyListeners();
  }

  void pause() {
    if (state != RecState.running) return;
    _advanceClock(DateTime.now());
    state = RecState.paused;
    _paceWindow.clear();
    HapticFeedback.mediumImpact();
    _say([isBike ? 'Pedal pausado.' : 'Corrida pausada.']);
    _notify(force: true);
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
    final msg = _coach.onResume(moving);
    _say(['Retomando.', msg]);
    _showCoach(msg);
    _notify(force: true);
    notifyListeners();
  }

  void markLap() {
    if (!isActive) return;
    _closeLap(manual: true);
    HapticFeedback.heavyImpact();
    final l = laps.last;
    _say(['Volta ${l.index}.', ...Speech.duration(l.sec)]);
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
      final bye = _coach.onFinish(moving);
      _say([isBike ? 'Pedal encerrado.' : 'Corrida encerrada.', ...Speech.distance(distance), bye]);
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
      calories: Calc.caloriesFor(a.sport, weightKg, dist, mov),
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
      _notify();
      notifyListeners();
    });
  }

  Future<void> _stopStream() async {
    RunNotification.cancel();
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
    // Descarta localização simulada, pontos antigos do cache (de antes do início)
    // e repetidos/fora de ordem.
    if (p.isMocked) return;
    final st = startTime;
    if (st != null && t.isBefore(st.subtract(const Duration(seconds: 2)))) return;
    final prevRaw = _lastRawTime;
    if (prevRaw != null && !t.isAfter(prevRaw)) return;
    _lastRawTime = t;

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
          _say(['Pausa automática.']);
          _notify(force: true);
        } else {
          _clock = now;
          autoPaused = false;
          _say(['Retomando.']);
          _notify(force: true);
        }
      }
    }
    _advanceClock(now);

    // Ponto impreciso com a pessoa parada só atrapalha.
    if (p.accuracy > GpsFilter.maxAccuracyM && v < _autoPause.below) {
      notifyListeners();
      return;
    }
    if (p.accuracy > GpsFilter.maxInputAccuracyM) {
      notifyListeners();
      return;
    }
    if (_segmentBreak) _smoother.reset();
    final sm = _smoother.update(p.latitude, p.longitude, p.accuracy, t);

    final verdict = GpsFilter.check(
      accuracy: p.accuracy,
      lat: sm.lat,
      lon: sm.lon,
      time: t,
      lastAccepted: _segmentBreak ? null : last,
      maxSpeed: config.sport.maxSpeedMps,
    );
    if (verdict != GpsVerdict.accept) {
      if (verdict == GpsVerdict.impossibleJump) _smoother.reset();
      notifyListeners();
      return;
    }

    var d = 0.0;
    if (last != null && !_segmentBreak && !autoPaused) {
      d = Calc.haversine(last.lat, last.lon, sm.lat, sm.lon);
    }
    _segmentBreak = false;
    distance += d;
    final point = TrackPoint(
      time: t,
      lat: sm.lat,
      lon: sm.lon,
      alt: p.altitude == 0 || p.altitudeAccuracy > 20 ? null : p.altitude,
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
      final k = currentKmh;
      if (k != null && k < config.sport.maxSpeedMps * 3.6 && moving > 30) maxKmh = k > maxKmh ? k : maxKmh;
      _checkSplits();
      _checkAutoLap();
      _checkGoal();
      final gp = goalProgress;
      if (gp != null && gp < 1) {
        final msg = _coach.onProgress(gp, moving);
        if (msg != null) {
          _say([msg]);
          _showCoach(msg);
        }
      }
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
      final km = splits.length;
      final prev = splits.length > 1 ? splits.sublist(0, splits.length - 1) : const <Split>[];
      final avgPrev = prev.isEmpty ? null : prev.fold<double>(0, (t, x) => t + x.sec) / prev.length;
      final every = config.voiceEveryKm < 1 ? 1 : config.voiceEveryKm;
      final announce = km % every == 0;
      final msg = announce ? _coach.onKm(km, moving, splitSec: sec, avgPrevSec: avgPrev, every: every) : null;
      if (config.voice && announce && isBike) {
        _say([
          Speech.kmCount(km),
          'Tempo',
          ...Speech.duration(moving),
          'Velocidade média',
          Speech.kmh(avgKmh ?? 0),
          msg,
        ]);
      } else if (config.voice && announce) {
        _say([
          Speech.kmCount(km),
          'Tempo',
          ...Speech.duration(moving),
          'Último quilômetro em',
          ...Speech.duration(sec),
          'Pace médio',
          ...Speech.duration(avgPace ?? 0),
          msg,
        ]);
      }
      _showCoach(msg);
      _notify(force: true);
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
      final msg = _coach.onGoalReached(moving);
      _say(['Meta atingida!', msg], force: true);
      _showCoach(msg ?? 'Meta atingida!');
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

  void _showCoach(String? msg) {
    if (msg == null) return;
    coachMessage = msg;
    coachMessageAt = DateTime.now();
  }

  /// Frase a mostrar agora (some depois de 4 s).
  String? get visibleCoachMessage {
    final at = coachMessageAt;
    if (at == null || DateTime.now().difference(at).inSeconds >= 4) return null;
    return coachMessage;
  }

  // ---------------- Voz ----------------

  Future<void> _initTts() => _speaker.init(VoiceService.natural);

  void _say(List<String?> parts, {bool force = false}) {
    if (!config.voice && !force) return;
    _speaker.say(parts);
  }


  void _applySport() {
    _autoPause.setSport(config.sport);
    _smoother = GpsSmoother(qq: config.sport.smootherQ);
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
    maxKmh = 0;
    accuracy = null;
    speed = null;
    autoPaused = false;
    gpsWarning = null;
    coachMessage = null;
    coachMessageAt = null;
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
    _smoother.reset();
    _lastRawTime = null;
    _lastNotify = null;
    RunNotification.cancel();
  }

  // ---------------- Notificação ao vivo ----------------

  DateTime? _lastNotify;

  void _notify({bool force = false}) {
    if (!isActive) return;
    final now = DateTime.now();
    final last = _lastNotify;
    if (!force && last != null && now.difference(last).inSeconds < 4) return;
    _lastNotify = now;
    final km = Fmt.km(distance);
    final stopped = state == RecState.paused || autoPaused;
    final title = state == RecState.paused
        ? 'Pausada · $km km'
        : autoPaused
            ? 'Pausa automática · $km km'
            : isBike
                ? 'Pedalando · $km km'
                : 'Correndo · $km km';
    final lines = <String>[];
    if (isBike) {
      lines.add(stopped
          ? 'Tempo ${Fmt.duration(moving)} · Média ${Fmt.kmh(avgKmh)} km/h'
          : 'Velocidade ${Fmt.kmh(currentKmh)} km/h · Média ${Fmt.kmh(avgKmh)} km/h');
    } else if (stopped) {
      lines.add('Tempo ${Fmt.duration(moving)} · Pace médio ${Fmt.pace(avgPace)} /km');
    } else {
      lines.add('Pace ${Fmt.pace(currentPace)} /km · Média ${Fmt.pace(avgPace)} /km');
    }
    final gp = goalProgress;
    if (gp != null) {
      lines.add(gp >= 1
          ? 'Meta atingida!'
          : config.goalType == GoalType.distance
              ? 'Meta: $km de ${Fmt.km(config.goalValue)} km'
              : 'Meta: ${Fmt.duration(moving)} de ${Fmt.duration(config.goalValue)}');
    }
    if (gpsWarning != null && !stopped) lines.add(gpsWarning!);
    RunNotification.show(
      title: title,
      text: lines.join('\n'),
      chip: '$km km',
      paused: stopped,
      movingSec: moving,
      progress: gp,
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ticker?.cancel();
    super.dispose();
  }
}
