import 'dart:math' as math;

/// Estilo das mensagens durante a corrida.
enum CoachStyle { energetic, gentle, discreet, off }

extension CoachStyleX on CoachStyle {
  String get key => name;
  String get label => switch (this) {
        CoachStyle.energetic => 'Energético',
        CoachStyle.gentle => 'Acolhedor',
        CoachStyle.discreet => 'Discreto (só números)',
        CoachStyle.off => 'Desligado',
      };
  String get hint => switch (this) {
        CoachStyle.energetic => 'Frases animadas de incentivo',
        CoachStyle.gentle => 'Frases calmas, no seu ritmo',
        CoachStyle.discreet => 'Só tempo, distância e pace',
        CoachStyle.off => 'Nenhuma frase',
      };
  bool get speaksPhrases => this == CoachStyle.energetic || this == CoachStyle.gentle;

  static CoachStyle parse(String? s) =>
      CoachStyle.values.firstWhere((e) => e.name == s, orElse: () => CoachStyle.energetic);
}

/// Momentos em que o PACE pode incentivar o corredor.
enum CoachMoment { start, firstKm, everyFewKm, q25, q50, q75, lastStretch, goalReached, resume, faster, finish, race }

/// Frases por momento e estilo (curtas, para ouvir no meio do esforço).
class CoachPhrases {
  static const Map<CoachMoment, List<String>> energetic = {
    CoachMoment.start: ['Vamos começar! Você consegue!', 'Bora! Esse treino é seu!', 'Vamos lá! Um passo de cada vez.'],
    CoachMoment.firstKm: ['Excelente começo! Continue assim!', 'Primeiro quilômetro feito. Muito bem!'],
    CoachMoment.everyFewKm: [
      'Você está indo muito bem!',
      'Continue, você está no caminho certo!',
      'Confie no seu ritmo. Você consegue!',
      'Você é mais forte do que imagina.',
      'Seu esforço está fazendo a diferença.',
      'Mantenha o foco. Você está indo muito bem!',
      'Mais um passo, mais uma conquista!',
      'Você está evoluindo!',
      'Força! Está dando certo!',
      'O esforço de agora será o orgulho de depois.',
      'Você está escrevendo sua história, um quilômetro por vez.',
    ],
    CoachMoment.q25: ['Você está indo muito bem!', 'Um quarto do caminho. Continue assim!'],
    CoachMoment.q50: ['Metade do caminho! Olha só até onde você chegou!', 'Metade feita. Você está fazendo acontecer!'],
    CoachMoment.q75: ['Falta pouco! Você está quase lá!', 'Continue firme, está quase lá!'],
    CoachMoment.lastStretch: [
      'Só mais um pouquinho. Você consegue!',
      'Você chegou até aqui. Termine com orgulho!',
      'Mais alguns passos e essa conquista será sua!',
    ],
    CoachMoment.goalReached: [
      'Você conseguiu! Mais uma conquista para sua história!',
      'Meta concluída! Orgulhe-se do que fez hoje!',
    ],
    CoachMoment.resume: ['Respire fundo. Bora continuar!', 'De volta ao ritmo. Você consegue!'],
    CoachMoment.faster: ['Seu ritmo está ótimo!', 'Que ritmo! Você está mandando muito bem!'],
    CoachMoment.finish: [
      'Você começou. Você continuou. E terminou!',
      'Excelente trabalho! Mais uma corrida para a conta.',
      'Termine sabendo que deu o seu melhor!',
    ],
    CoachMoment.race: [
      'Imagine a sensação de cruzar a linha de chegada!',
      'A linha de chegada está cada vez mais perto!',
    ],
  };

  static const Map<CoachMoment, List<String>> gentle = {
    CoachMoment.start: ['Vamos começar, no seu tempo.', 'Bom treino. Respire e aproveite.'],
    CoachMoment.firstKm: ['Bom começo. Siga assim, com calma.', 'Primeiro quilômetro feito. Tudo no seu ritmo.'],
    CoachMoment.everyFewKm: [
      'Confie no seu ritmo.',
      'Um passo de cada vez, sem pressa.',
      'Você está indo bem.',
      'Respire fundo e siga tranquilo.',
      'Cada quilômetro conta.',
      'Não importa a velocidade. Importa continuar.',
      'Esse momento é seu. Aproveite cada passo.',
      'Faça por você, no seu tempo.',
    ],
    CoachMoment.q25: ['Um quarto do caminho. Siga no seu ritmo.'],
    CoachMoment.q50: ['Metade do caminho. Você está indo bem.'],
    CoachMoment.q75: ['Falta pouco. Continue tranquilo.'],
    CoachMoment.lastStretch: ['Só mais um pouco. Aproveite esses últimos passos.'],
    CoachMoment.goalReached: ['Meta concluída. Que bom treino!', 'Você conseguiu. Aproveite a sensação.'],
    CoachMoment.resume: ['Retomando com calma.', 'Respire e volte no seu ritmo.'],
    CoachMoment.faster: ['Ritmo bonito. Siga assim.'],
    CoachMoment.finish: ['Treino concluído. Cuide-se e hidrate-se.', 'Mais uma corrida feita. Parabéns pelo cuidado com você.'],
    CoachMoment.race: ['A chegada está perto. Aproveite.'],
  };

  /// Frases do Guará para a abertura do app e o resultado da corrida.
  static const daily = [
    'Seu ritmo, sua jornada, sua conquista.',
    'Hoje é mais um dia para superar seus limites.',
    'Não importa a velocidade. Importa não parar de evoluir.',
    'Você está escrevendo sua própria história, um quilômetro por vez.',
    'O importante não é chegar primeiro, é continuar avançando.',
    'Cada quilômetro percorrido é uma prova da sua dedicação.',
    'O seu único concorrente é quem você era ontem.',
    'Constância vence pressa.',
  ];

  static const resultTitles = ['Mandou bem!', 'Excelente trabalho!', 'Mais uma conquista!', 'Você conseguiu!'];
  static const resultLines = [
    'Termine sabendo que deu o seu melhor.',
    'Cada corrida é uma conquista pessoal.',
    'Você está mais perto do seu objetivo do que ontem.',
    'O resultado vem de pequenas escolhas como essa.',
    'Orgulhe-se do que fez hoje.',
  ];
}

/// Decide quando e o que falar durante a corrida.
///  - no máximo uma frase por km e nunca duas em menos de 60 s;
///  - a mesma frase não se repete na mesma corrida;
///  - percentuais (25/50/75/90%) só com meta de distância ou tempo;
///  - corrida livre: 1º km e depois a cada 2 km.
class Coach {
  final CoachStyle style;
  final bool hasGoal;
  final bool isRace;
  final math.Random _rnd;
  final _used = <String>{};
  final _firedPct = <int>{};
  double? _lastSpokeMov;
  int _lastKmSpoken = -1;

  Coach({required this.style, this.hasGoal = false, this.isRace = false, math.Random? random})
      : _rnd = random ?? math.Random();

  static const minGapSec = 60.0;

  Map<CoachMoment, List<String>> get _bank =>
      style == CoachStyle.gentle ? CoachPhrases.gentle : CoachPhrases.energetic;

  String? _pick(CoachMoment m, double mov, {bool force = false}) {
    if (!style.speaksPhrases) return null;
    if (!force && _lastSpokeMov != null && mov - _lastSpokeMov! < minGapSec) return null;
    final list = _bank[m] ?? const <String>[];
    final free = list.where((p) => !_used.contains(p)).toList();
    if (free.isEmpty) return null;
    final p = free[_rnd.nextInt(free.length)];
    _used.add(p);
    _lastSpokeMov = mov;
    return p;
  }

  String? onStart() => _pick(CoachMoment.start, 0, force: true);

  String? onResume(double mov) => _pick(CoachMoment.resume, mov);

  /// Ao completar o km [km]. [splitSec] é o tempo deste km e [avgPrevSec] a
  /// média dos kms anteriores (nulo no 1º km).
  String? onKm(int km, double mov, {required double splitSec, double? avgPrevSec}) {
    if (_lastKmSpoken == km) return null;
    String? p;
    if (km == 1) {
      p = _pick(CoachMoment.firstKm, mov);
    } else if (!hasGoal && km.isOdd) {
      final faster = avgPrevSec != null && splitSec < avgPrevSec * 0.97;
      p = _pick(faster ? CoachMoment.faster : CoachMoment.everyFewKm, mov);
    }
    if (p != null) _lastKmSpoken = km;
    return p;
  }

  /// Progresso da meta (0..1). Fala em 25, 50, 75 e 90%.
  String? onProgress(double progress, double mov) {
    if (!hasGoal) return null;
    for (final (pct, m) in [
      (90, isRace ? CoachMoment.race : CoachMoment.lastStretch),
      (75, CoachMoment.q75),
      (50, CoachMoment.q50),
      (25, CoachMoment.q25),
    ]) {
      if (progress * 100 >= pct && !_firedPct.contains(pct)) {
        // Marca este e os anteriores, para não falar marcos atrasados em sequência.
        _firedPct.addAll([25, 50, 75, 90].where((x) => x <= pct));
        return _pick(m, mov, force: pct == 90);
      }
    }
    return null;
  }

  String? onGoalReached(double mov) => _pick(CoachMoment.goalReached, mov, force: true);

  String? onFinish(double mov) => _pick(CoachMoment.finish, mov, force: true);
}
