import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pace/domain/coach.dart';
import 'package:pace/services/speech.dart';

void main() {
  final clips = Directory('assets/voz')
      .listSync()
      .map((f) => f.uri.pathSegments.last)
      .where((n) => n.endsWith('.mp3'))
      .map((n) => n.substring(0, n.length - 4))
      .toSet();

  void covered(List<String> parts) {
    for (final p in parts) {
      expect(clips, contains(Speech.key(p)), reason: 'falta gravar: "$p"');
    }
  }

  test('chave igual à do gerador', () {
    expect(Speech.key('Último quilômetro em'), 'ultimo_quilometro_em');
    expect(Speech.key('03 quilômetros.'), '03_quilometros');
    expect(Speech.key('Bora! Esse treino é seu!'), 'bora_esse_treino_e_seu');
  });

  test('durações em trechos', () {
    expect(Speech.duration(0), ['0 segundos']);
    expect(Speech.duration(61), ['1 minuto', 'e 1 segundo']);
    expect(Speech.duration(3600), ['1 hora']);
    expect(Speech.duration(3660), ['1 hora', 'e 1 minuto']);
    expect(Speech.duration(3725), ['1 hora', '2 minutos', 'e 5 segundos']);
    expect(Speech.distance(13030), ['13 vírgula', '03 quilômetros.']);
  });

  test('todas as falas possíveis estão gravadas', () {
    for (final m in [CoachPhrases.energetic, CoachPhrases.gentle]) {
      for (final list in m.values) {
        covered(list);
      }
    }
    covered(['Corrida iniciada.', 'Corrida pausada.', 'Corrida retomada.', 'Retomando.', 'Pausa automática.',
      'Corrida encerrada.', 'Meta atingida!', 'Tempo', 'Último quilômetro em', 'Pace médio']);
    for (var s = 0; s < 6 * 3600; s += 7) {
      covered(Speech.duration(s.toDouble()));
    }
    for (var m = 0; m < 100000; m += 10) {
      covered(Speech.distance(m.toDouble()));
    }
    for (var km = 1; km <= 100; km++) {
      covered([Speech.kmCount(km), 'Volta $km.']);
    }
  });
}
