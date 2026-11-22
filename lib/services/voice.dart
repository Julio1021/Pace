import 'package:flutter_tts/flutter_tts.dart';

/// Uma voz de leitura instalada no aparelho.
class PaceVoice {
  final String name;
  final String locale;
  final bool online;
  const PaceVoice(this.name, this.locale, {this.online = false});

  Map<String, String> get asMap => {'name': name, 'locale': locale};

  /// Palpite de voz feminina pelos nomes usados pelos motores do Google e da Samsung.
  bool get likelyFemale {
    final n = name.toLowerCase();
    if (n.contains('female') || n.contains('femin') || n.contains('mulher')) return true;
    if (RegExp(r'smtf\d').hasMatch(n)) return true; // Samsung: SMTf = feminina
    if (n.contains('-x-afs') || n.contains('-x-pte')) return true; // Google pt-BR
    return false;
  }

  bool get likelyMale {
    final n = name.toLowerCase();
    return n.contains('male') && !n.contains('female') ||
        RegExp(r'smtm\d').hasMatch(n) ||
        n.contains('-x-ptd');
  }
}

/// Configura a voz das falas: a escolhida pelo usuário ou, no automático, uma feminina em pt-BR.
class VoiceService {
  /// Valor salvo para a voz natural gravada (Francisca), padrão.
  static const natural = '';

  /// Valor salvo para "voz feminina do celular, escolhida automaticamente".
  static const auto = 'auto';

  static Future<List<PaceVoice>> portugueseVoices(FlutterTts tts) async {
    try {
      final raw = await tts.getVoices;
      if (raw is! List) return [];
      final out = <PaceVoice>[];
      final seen = <String>{};
      for (final v in raw) {
        if (v is! Map) continue;
        final name = '${v['name'] ?? ''}';
        final locale = '${v['locale'] ?? ''}';
        if (name.isEmpty || !locale.toLowerCase().startsWith('pt')) continue;
        if (!seen.add(name)) continue;
        final net = '${v['network_required'] ?? ''}';
        out.add(PaceVoice(name, locale, online: net == '1' || net == 'true' || name.contains('network')));
      }
      int score(PaceVoice v) =>
          (v.locale.toLowerCase().replaceAll('_', '-') == 'pt-br' ? 0 : 10) +
          (v.likelyFemale ? 0 : v.likelyMale ? 4 : 2) +
          (v.online ? 1 : 0);
      out.sort((a, b) {
        final c = score(a).compareTo(score(b));
        return c != 0 ? c : a.name.compareTo(b.name);
      });
      return out;
    } catch (_) {
      return [];
    }
  }

  /// Aplica a voz salva (ou a melhor feminina disponível). Retorna o nome aplicado.
  static Future<String?> apply(FlutterTts tts, String saved) async {
    await tts.setLanguage('pt-BR');
    await tts.setSpeechRate(0.5);
    final voices = await portugueseVoices(tts);
    if (voices.isEmpty) return null;
    PaceVoice? pick;
    if (saved != auto && saved != natural) {
      for (final v in voices) {
        if (v.name == saved) pick = v;
      }
    }
    pick ??= voices.firstWhere((v) => v.likelyFemale, orElse: () => voices.first);
    try {
      await tts.setVoice(pick.asMap);
      await tts.setPitch(1.0);
    } catch (_) {}
    return pick.name;
  }
}
