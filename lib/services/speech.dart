import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';

import 'voice.dart';

/// Monta as falas em trechos que existem gravados em assets/voz.
class Speech {
  static const dir = 'assets/voz/';

  /// Mesma normalização de tool/vozes/gerar.py.
  static String key(String s) {
    const from = 'áàâãäéèêëíìîïóòôõöúùûüç';
    const to = 'aaaaaeeeeiiiiooooouuuuc';
    final b = StringBuffer();
    for (final ch in s.toLowerCase().split('')) {
      final i = from.indexOf(ch);
      b.write(i >= 0 ? to[i] : ch);
    }
    return b
        .toString()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }

  /// "1 hora", "16 minutos", "e 20 segundos"…
  static List<String> duration(double seconds) {
    final s = seconds.round();
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    final out = <String>[];
    if (h > 0) out.add('$h ${h == 1 ? 'hora' : 'horas'}');
    if (m > 0) out.add('${h > 0 && sec == 0 ? 'e ' : ''}$m ${m == 1 ? 'minuto' : 'minutos'}');
    if (sec > 0 || out.isEmpty) {
      out.add('${out.isEmpty ? '' : 'e '}$sec ${sec == 1 ? 'segundo' : 'segundos'}');
    }
    return out;
  }

  /// "13 vírgula", "03 quilômetros."
  static List<String> distance(double meters) {
    final c = (meters / 10).round(); // centésimos de km
    return ['${c ~/ 100} vírgula', '${(c % 100).toString().padLeft(2, '0')} quilômetros.'];
  }

  static String kmCount(int km) => '$km ${km == 1 ? 'quilômetro' : 'quilômetros'}.';
}

/// Toca as falas gravadas (voz natural) em fila; se faltar algum trecho
/// ou o usuário escolher uma voz do celular, usa o leitor do aparelho.
class Speaker {
  // A sessão de áudio é ativada/desativada por nós, em volta de cada fala.
  final _player = AudioPlayer(handleAudioSessionActivation: false, handleInterruptions: false);

  /// Fala como um GPS: pede para a música "abaixar" (sem pausar) e devolve o volume no fim.
  static const _attrs = AndroidAudioAttributes(
    contentType: AndroidAudioContentType.speech,
    usage: AndroidAudioUsage.assistanceNavigationGuidance,
  );
  static const _session = AudioSessionConfiguration(
    avAudioSessionCategory: AVAudioSessionCategory.playback,
    avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.duckOthers,
    avAudioSessionMode: AVAudioSessionMode.spokenAudio,
    avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation,
    androidAudioAttributes: _attrs,
    androidAudioFocusGainType: AndroidAudioFocusGainType.gainTransientMayDuck,
    androidWillPauseWhenDucked: false,
  );
  final _queue = <List<String>>[];
  Set<String> _clips = {};
  FlutterTts? _tts;
  String _voice = VoiceService.natural;
  bool _busy = false;
  bool _ready = false;

  Future<void> init(String voiceName) async {
    _voice = voiceName;
    if (_ready) {
      if (_tts != null) await VoiceService.apply(_tts!, _voice);
      return;
    }
    _ready = true;
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      _clips = manifest
          .listAssets()
          .where((a) => a.startsWith(Speech.dir) && a.endsWith('.mp3'))
          .map((a) => a.substring(Speech.dir.length, a.length - 4))
          .toSet();
    } catch (_) {}
    try {
      final session = await AudioSession.instance;
      await session.configure(_session);
      await _player.setAndroidAudioAttributes(_attrs);
    } catch (_) {}
    try {
      final tts = FlutterTts();
      await tts.awaitSpeakCompletion(true);
      await VoiceService.apply(tts, _voice);
      _tts = tts;
    } catch (_) {}
  }

  bool hasAll(List<String> parts) => parts.every((p) => _clips.contains(Speech.key(p)));

  void say(List<String?> parts) {
    final p = [for (final x in parts) if (x != null && x.trim().isNotEmpty) x.trim()];
    if (p.isEmpty) return;
    _queue.add(p);
    if (!_busy) unawaited(_drain());
  }

  Future<void> stop() async {
    _queue.clear();
    try {
      await _player.stop();
      await _tts?.stop();
    } catch (_) {}
  }

  Future<void> _drain() async {
    _busy = true;
    try {
      while (_queue.isNotEmpty) {
        final parts = _queue.removeAt(0);
        try {
          if (_voice == VoiceService.natural && hasAll(parts)) {
            await _playClips(parts);
          } else if (_tts != null) {
            // Reserva (trecho sem gravação): também abaixa a música em vez de pausar.
            final session = await AudioSession.instance;
            await session.setActive(true);
            try {
              await _tts!.speak(parts.join(' '));
            } finally {
              await session.setActive(false);
            }
          }
        } catch (_) {}
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _playClips(List<String> parts) async {
    final session = await AudioSession.instance;
    await _player.setAudioSources(
      [for (final p in parts) AudioSource.asset('${Speech.dir}${Speech.key(p)}.mp3')],
      preload: true,
    );
    await _player.seek(Duration.zero, index: 0);
    await session.setActive(true);
    try {
      // play() termina quando a lista acaba (ou para); não precisa esperar outro evento.
      unawaited(_player.play());
      await _player.processingStateStream
          .firstWhere((s) => s == ProcessingState.completed)
          .timeout(const Duration(seconds: 40), onTimeout: () => ProcessingState.completed);
      await _player.stop();
    } finally {
      // Devolve o foco: a música volta ao volume normal.
      await session.setActive(false);
    }
  }
}
