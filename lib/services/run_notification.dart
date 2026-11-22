import 'package:flutter/services.dart';

/// Notificação "ao vivo" da corrida: aparece na barra e na tela de bloqueio,
/// com tempo correndo (cronômetro do próprio Android), distância, pace,
/// barra da meta e botão Pausar/Retomar. No Android 16 vira um Live Update.
class RunNotification {
  static const _ch = MethodChannel('pace/run_notification');
  static void Function(String action)? onAction;
  static bool _ready = false;

  static void _init() {
    if (_ready) return;
    _ready = true;
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'action') onAction?.call('${call.arguments}');
      return null;
    });
  }

  static Future<void> show({
    required String title,
    required String text,
    required String chip,
    required bool paused,
    required double movingSec,
    double? progress,
  }) async {
    _init();
    try {
      await _ch.invokeMethod('show', {
        'title': title,
        'text': text,
        'chip': chip,
        'paused': paused,
        'movingMs': (movingSec * 1000).round(),
        'progress': progress == null ? -1 : (progress.clamp(0.0, 1.0) * 1000).round(),
      });
    } catch (_) {
      // Sem a parte nativa (ex.: testes) a corrida segue normalmente.
    }
  }

  static Future<void> cancel() async {
    try {
      await _ch.invokeMethod('cancel');
    } catch (_) {}
  }
}
