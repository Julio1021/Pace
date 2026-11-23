import 'models.dart';

/// Um treino de um plano: semana, número na semana, tipo, alvo e instruções.
class PlanSession {
  final int week; // 1..N
  final int n; // 1..3
  final String type; // um dos trainingTypes
  final bool byTime; // alvo em minutos (true) ou km (false)
  final double value; // km ou minutos
  final String detail;

  const PlanSession(this.week, this.n, this.type, this.byTime, this.value, this.detail);

  String get target => byTime
      ? '${value.round()} min'
      : '${value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1).replaceAll('.', ',')} km';

  String get title => '$type · $target';

  /// A corrida conta para este treino se chegou a 80% do alvo.
  bool satisfiedBy(Activity a) =>
      byTime ? a.movingSec >= value * 60 * 0.8 : a.distanceM >= value * 1000 * 0.8;
}

class TrainingPlan {
  final String id;
  final String name;
  final String level;
  final String summary;
  final String forWho;
  final int weeks;
  final List<PlanSession> sessions;

  const TrainingPlan({
    required this.id,
    required this.name,
    required this.level,
    required this.summary,
    required this.forWho,
    required this.weeks,
    required this.sessions,
  });

  static TrainingPlan? byId(String id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return null;
  }

  static List<PlanSession> _build(List<List<(String, bool, double, String)>> weeks) => [
        for (var w = 0; w < weeks.length; w++)
          for (var i = 0; i < weeks[w].length; i++)
            PlanSession(w + 1, i + 1, weeks[w][i].$1, weeks[w][i].$2, weeks[w][i].$3, weeks[w][i].$4),
      ];

  static const _leve = 'Corrida leve';
  static const _ritmo = 'Treino de ritmo';
  static const _int = 'Intervalado';
  static const _longo = 'Rodagem longa';
  static const _prova = 'Prova';
  static const _aq = 'Aqueça 5 min andando ou trotando.';

  static final all = <TrainingPlan>[
    TrainingPlan(
      id: 'primeiros5k',
      name: 'Primeiros 5 km',
      level: 'Iniciante',
      summary: '8 semanas · 3 treinos por semana',
      forWho: 'Para quem está começando ou voltando. Alterna corrida e caminhada até correr 5 km sem parar.',
      weeks: 8,
      sessions: _build([
        for (final (w, txt, min) in [
          (1, 'Corra 1 min e caminhe 2 min. Repita 8 vezes.', 24.0),
          (2, 'Corra 2 min e caminhe 2 min. Repita 6 vezes.', 24.0),
          (3, 'Corra 3 min e caminhe 2 min. Repita 5 vezes.', 25.0),
          (4, 'Corra 5 min e caminhe 2 min. Repita 4 vezes.', 28.0),
          (5, 'Corra 8 min e caminhe 2 min. Repita 3 vezes.', 30.0),
          (6, 'Corra 12 min e caminhe 2 min. Repita 2 vezes.', 28.0),
          (7, 'Corra 20 min sem parar, num ritmo de conversa.', 25.0),
        ])
          [
            for (var i = 0; i < 3; i++) (_leve, true, min, '$_aq $txt${w == 1 && i == 0 ? ' Sem pressa: o objetivo é completar.' : ''}'),
          ],
        [
          (_leve, true, 25, '$_aq Corra 25 min sem parar.'),
          (_leve, true, 20, 'Corrida bem leve de 20 min para chegar descansado.'),
          (_prova, false, 5, 'O grande dia: 5 km! Comece devagar e acelere só no último km.'),
        ],
      ]),
    ),
    TrainingPlan(
      id: 'rapido5k',
      name: '5 km mais rápido',
      level: 'Intermediário',
      summary: '6 semanas · 3 treinos por semana',
      forWho: 'Para quem já corre 5 km e quer baixar o tempo com tiros e treinos de ritmo.',
      weeks: 6,
      sessions: _build([
        [
          (_leve, false, 4, 'Ritmo confortável, dá para conversar.'),
          (_int, true, 30, '$_aq 6 × 400 m forte com 2 min trotando entre eles.'),
          (_leve, false, 5, 'Rodagem leve e constante.'),
        ],
        [
          (_leve, false, 4, 'Ritmo confortável.'),
          (_ritmo, true, 30, '$_aq 15 min em ritmo forte mas controlado, depois solte.'),
          (_leve, false, 6, 'Rodagem leve.'),
        ],
        [
          (_leve, false, 5, 'Ritmo confortável.'),
          (_int, true, 35, '$_aq 5 × 800 m forte com 2 min trotando.'),
          (_leve, false, 6, 'Rodagem leve.'),
        ],
        [
          (_leve, false, 4, 'Semana mais leve para o corpo assimilar.'),
          (_ritmo, true, 30, '$_aq 2 × 8 min forte com 3 min leve.'),
          (_leve, false, 5, 'Rodagem leve.'),
        ],
        [
          (_leve, false, 5, 'Ritmo confortável.'),
          (_int, true, 35, '$_aq 4 × 1 km no ritmo que você quer para a prova, 2 min trotando.'),
          (_leve, false, 6, 'Rodagem leve.'),
        ],
        [
          (_leve, false, 4, 'Leve, só para soltar as pernas.'),
          (_leve, true, 20, 'Bem leve, com 4 acelerações curtas de 20 s no fim.'),
          (_prova, false, 5, 'Teste de 5 km: comece no ritmo-alvo e acelere no fim.'),
        ],
      ]),
    ),
    TrainingPlan(
      id: 'rumo10k',
      name: 'Rumo aos 10 km',
      level: 'Intermediário',
      summary: '8 semanas · 3 treinos por semana',
      forWho: 'Para quem já completa 5 km e quer chegar aos 10 km com segurança.',
      weeks: 8,
      sessions: _build([
        for (final (e, q, qd, l) in [
          (4.0, 30.0, '$_aq 6 × 1 min forte com 2 min leve.', 5.0),
          (4.0, 30.0, '$_aq 12 min em ritmo firme, depois solte.', 6.0),
          (5.0, 35.0, '$_aq 6 × 2 min forte com 2 min leve.', 7.0),
          (4.0, 30.0, 'Semana mais leve: 3 × 5 min firme com 2 min leve.', 5.0),
          (5.0, 35.0, '$_aq 20 min em ritmo firme.', 8.0),
          (5.0, 40.0, '$_aq 5 × 3 min forte com 2 min leve.', 9.0),
          (4.0, 30.0, 'Semana mais leve: 15 min firme.', 7.0),
        ])
          [
            (_leve, false, e, 'Ritmo de conversa.'),
            (qd.contains('×') ? _int : _ritmo, true, q, qd),
            (_longo, false, l, 'Devagar e constante. O importante é a distância.'),
          ],
        [
          (_leve, false, 4, 'Leve, para chegar descansado.'),
          (_leve, true, 20, 'Bem leve, com 4 acelerações curtas no fim.'),
          (_prova, false, 10, 'Seus 10 km! Comece mais lento do que tem vontade.'),
        ],
      ]),
    ),
    TrainingPlan(
      id: 'meia',
      name: 'Meia maratona',
      level: 'Avançado',
      summary: '12 semanas · 3 treinos por semana',
      forWho: 'Para quem já corre 10 km e quer completar os 21,1 km.',
      weeks: 12,
      sessions: _build([
        for (final (e, q, qd, l) in [
          (5.0, 40.0, '$_aq 6 × 3 min forte com 2 min leve.', 10.0),
          (6.0, 40.0, '$_aq 20 min em ritmo de meia maratona.', 11.0),
          (6.0, 45.0, '$_aq 5 × 1 km forte com 2 min leve.', 12.0),
          (5.0, 40.0, 'Semana mais leve: 15 min em ritmo firme.', 9.0),
          (6.0, 45.0, '$_aq 25 min em ritmo de meia.', 13.0),
          (7.0, 50.0, '$_aq 4 × 2 km em ritmo de meia, 3 min leve.', 15.0),
          (7.0, 50.0, '$_aq 6 × 1 km forte com 2 min leve.', 16.0),
          (5.0, 40.0, 'Semana mais leve: 20 min firme.', 12.0),
          (7.0, 55.0, '$_aq 30 min em ritmo de meia.', 17.0),
          (8.0, 55.0, '$_aq 3 × 3 km em ritmo de meia, 3 min leve.', 18.0),
          (6.0, 40.0, 'Começa a reduzir: 15 min em ritmo de meia.', 13.0),
        ])
          [
            (_leve, false, e, 'Ritmo de conversa.'),
            (qd.contains('×') ? _int : _ritmo, true, q, qd),
            (_longo, false, l, 'Devagar e constante. Hidrate-se a cada 30 min.'),
          ],
        [
          (_leve, false, 5, 'Leve, só para manter as pernas acordadas.'),
          (_leve, true, 20, 'Bem leve, com 4 acelerações curtas no fim.'),
          (_prova, false, 21.1, 'Dia da meia maratona! Os primeiros 5 km mais lentos que o planejado.'),
        ],
      ]),
    ),
  ];
}

/// Plano em andamento: qual, desde quando e quais treinos foram feitos (com a corrida que contou).
class ActivePlan {
  final String planId;
  final DateTime start; // local (dia)
  final Map<int, int> done; // índice do treino -> id da corrida (0 = marcado à mão)

  const ActivePlan({required this.planId, required this.start, this.done = const {}});

  TrainingPlan? get plan => TrainingPlan.byId(planId);

  int? get nextIndex {
    final p = plan;
    if (p == null) return null;
    for (var i = 0; i < p.sessions.length; i++) {
      if (!done.containsKey(i)) return i;
    }
    return null;
  }

  bool get finished => nextIndex == null;

  /// Semana do calendário em que o plano está (1..).
  int weekNow(DateTime now) => (DateTime(now.year, now.month, now.day).difference(start).inDays ~/ 7) + 1;

  ActivePlan copyWith({Map<int, int>? done}) => ActivePlan(planId: planId, start: start, done: done ?? this.done);

  Map<String, Object?> toJson() => {
        'id': planId,
        'start': '${start.year}-${start.month}-${start.day}',
        'done': {for (final e in done.entries) '${e.key}': e.value},
      };

  static ActivePlan? fromJson(Map<String, dynamic> j) {
    final parts = '${j['start']}'.split('-').map(int.tryParse).toList();
    if (parts.length != 3 || parts.contains(null)) return null;
    final d = <int, int>{};
    final raw = j['done'];
    if (raw is Map) {
      for (final e in raw.entries) {
        final k = int.tryParse('${e.key}');
        if (k != null) d[k] = (e.value as num?)?.toInt() ?? 0;
      }
    }
    return ActivePlan(planId: '${j['id']}', start: DateTime(parts[0]!, parts[1]!, parts[2]!), done: d);
  }

  /// Marca automaticamente os treinos com as corridas feitas desde o início do plano,
  /// em ordem: cada corrida conta para o próximo treino pendente se atingir 80% do alvo.
  ActivePlan autoMark(List<Activity> activities) {
    final p = plan;
    if (p == null) return this;
    final used = done.values.toSet();
    final asc = [
      for (final a in activities)
        if (a.id != null && !used.contains(a.id) && !a.start.toLocal().isBefore(start)) a
    ]..sort((a, b) => a.start.compareTo(b.start));
    final d = Map<int, int>.from(done);
    for (final a in asc) {
      int? next;
      for (var i = 0; i < p.sessions.length; i++) {
        if (!d.containsKey(i)) {
          next = i;
          break;
        }
      }
      if (next == null) break;
      if (p.sessions[next].satisfiedBy(a)) d[next] = a.id!;
    }
    return d.length == done.length ? this : copyWith(done: d);
  }
}
