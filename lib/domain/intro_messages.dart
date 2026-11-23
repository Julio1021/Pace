import 'dart:math' as math;

import '../core/format.dart';
import 'coach.dart';
import 'models.dart';
import 'stats.dart';

/// Como o Guará entra na tela de abertura.
enum IntroEntrance { runIn, runInRight, drop, peek, pop }

/// Recado da abertura: um título curto, a mensagem do momento e uma dica.
class IntroMessage {
  final String title;
  final String text;
  final String tip;
  final bool tipIsAdvice; // true = "Dica do Guará"; false = incentivo
  final GuaraPoseHint pose;
  final IntroEntrance entrance;
  const IntroMessage({
    required this.title,
    required this.text,
    required this.tip,
    required this.tipIsAdvice,
    required this.pose,
    required this.entrance,
  });

  /// Tempo para ler com calma: 2,5 s + ~65 ms por letra (entre 6 e 16 s).
  Duration get readingTime {
    final chars = title.length + text.length + tip.length;
    final ms = (2500 + chars * 65).clamp(6000, 16000);
    return Duration(milliseconds: ms);
  }
}

/// Pose sugerida (a interface converte para a pose do desenho).
enum GuaraPoseHint { wave, run, celebrate, sleep }

class IntroMessages {
  /// Dicas práticas (corrida e saúde).
  static const runTips = [
    'Beba água ao longo do dia, não só na hora do treino.',
    'Aqueça de 5 a 10 minutos antes de acelerar.',
    'Aumente o volume da semana aos poucos: no máximo uns 10% por semana.',
    'A maior parte dos treinos deve ser leve, conversando sem perder o fôlego.',
    'Dormir bem é parte do treino. É no descanso que o corpo evolui.',
    'Desconforto é normal; dor aguda não. Na dúvida, pare e descanse.',
    'Passadas curtas e rápidas cansam menos que passadas longas.',
    'Olhe para a frente, ombros soltos e braços relaxados.',
    'Tênis rodam em média 600 a 800 km. Fique de olho no seu.',
    'Fortalecer pernas e core duas vezes por semana previne lesões.',
    'Coma algo leve 1 a 2 horas antes de correr.',
    'Depois do treino, desacelere caminhando alguns minutos.',
    'No sol forte, prefira o começo da manhã ou o fim da tarde.',
    'À noite, use roupa clara ou refletiva para ser visto.',
    'Respire pelo nariz e pela boca. O importante é não prender o ar.',
    'Um dia de descanso por semana ajuda o corpo a se recuperar.',
    'Varie o percurso: subidas leves deixam as pernas mais fortes.',
    'Protetor solar e boné também fazem parte do equipamento.',
    'Comece devagar. Terminar mais rápido do que começou é sinal de bom ritmo.',
    'Depois de treinos longos, capriche na proteína e no carboidrato.',
  ];

  /// Dicas do pedal.
  static const bikeTips = [
    'Capacete sempre, até no passeio curto.',
    'Confira a calibragem dos pneus antes de sair.',
    'Pedale em giro leve: 80 a 90 pedaladas por minuto cansam menos.',
    'Selim na altura certa: perna quase esticada no ponto mais baixo.',
    'Em pedais longos, beba um pouco a cada 15 ou 20 minutos.',
    'À noite, luz branca na frente e vermelha atrás.',
    'Corrente limpa e lubrificada deixa o pedal mais leve.',
  ];

  /// Incentivos (além das frases diárias do treinador).
  static const cheers = [
    'Pequenos passos todos os dias viram grandes conquistas.',
    'Você não precisa ser rápido. Precisa começar.',
    'O treino mais difícil é o de sair de casa. O resto vem.',
    'Cada treino conta, até o mais curto.',
    'Seu corpo agradece cada quilômetro.',
    'Disciplina é lembrar o que você quer.',
    'Hoje você é mais forte do que ontem.',
    'Devagar também é ritmo. Continue.',
  ];

  /// Monta o recado do momento, sem repetir os últimos mostrados ([recent]).
  static IntroMessage pick({
    required String name,
    required DateTime now,
    required List<Activity> runs,
    required List<Activity> rides,
    required double weeklyGoalKm,
    required PeriodStats week,
    required List<String> recent,
    math.Random? random,
  }) {
    final rnd = random ?? math.Random();
    final first = name.trim().split(' ').first;
    final hello = now.hour < 5
        ? 'Boa madrugada'
        : now.hour < 12
            ? 'Bom dia'
            : now.hour < 18
                ? 'Boa tarde'
                : 'Boa noite';
    final title = first.isEmpty ? '$hello!' : '$hello, $first!';

    // 1) Mensagem do momento, pelos dados reais.
    var pose = GuaraPoseHint.wave;
    String text;
    final all = [...runs, ...rides]..sort((a, b) => b.start.compareTo(a.start));
    if (all.isEmpty) {
      text = 'Que bom ter você aqui. Seu primeiro treino está a um toque.';
    } else {
      final last = all.first;
      final today = Periods.dayStart(now);
      final daysSince = today.difference(Periods.dayStart(last.start.toLocal())).inDays;
      final km = week.distanceM / 1000;
      final left = weeklyGoalKm - km;
      final what = last.isBike ? 'pedal' : 'corrida';
      final options = <(String, GuaraPoseHint)>[];
      if (now.hour >= 22 || now.hour < 5) {
        options.add(('Hora de descansar. Amanhã a gente treina com energia.', GuaraPoseHint.sleep));
      }
      if (weeklyGoalKm > 0 && km >= weeklyGoalKm) {
        options.add(('Meta da semana batida com ${Fmt.kmUnit(week.distanceM, decimals: 1)}. Que orgulho!', GuaraPoseHint.celebrate));
      } else if (weeklyGoalKm > 0 && left > 0 && week.count > 0) {
        options.add(('Faltam ${Fmt.kmUnit(left * 1000, decimals: 1)} para a meta da semana. Você consegue!', GuaraPoseHint.wave));
      }
      if (daysSince == 0) {
        options.add(('Treino de hoje feito: ${Fmt.kmUnit(last.distanceM)} de $what. Agora é recuperar bem.', GuaraPoseHint.celebrate));
      } else if (daysSince == 1) {
        options.add(('Ontem foram ${Fmt.kmUnit(last.distanceM)} de $what. Mandou bem!', GuaraPoseHint.celebrate));
      } else if (daysSince >= 4) {
        options.add(('Faz $daysSince dias desde o último treino. Que tal algo leve hoje?', GuaraPoseHint.run));
      } else {
        options.add(('Seu último treino foi há $daysSince dias. Bora manter o ritmo?', GuaraPoseHint.run));
      }
      if (runs.length > 1 && !last.isBike) {
        final longest = runs.map((a) => a.distanceM).reduce(math.max);
        if (last.distanceM >= longest - 0.5) {
          options.add(('Sua última corrida foi a mais longa de todas: ${Fmt.kmUnit(last.distanceM)}!', GuaraPoseHint.celebrate));
        }
      }
      if (week.count >= 3) {
        options.add(('Já são ${week.count} treinos nesta semana. Constância é tudo!', GuaraPoseHint.celebrate));
      }
      final unseen = options.where((o) => !recent.contains(o.$1)).toList();
      final chosen = (unseen.isEmpty ? options : unseen)[rnd.nextInt((unseen.isEmpty ? options : unseen).length)];
      text = chosen.$1;
      pose = chosen.$2;
    }

    // 2) Dica ou incentivo, alternando e sem repetir os recentes.
    final bikeFan = rides.isNotEmpty && (runs.isEmpty || rides.first.start.isAfter(runs.first.start));
    final advice = rnd.nextBool();
    final pool = advice
        ? [...runTips, if (bikeFan) ...bikeTips]
        : [...cheers, ...CoachPhrases.daily];
    final fresh = pool.where((t) => !recent.contains(t)).toList();
    final list = fresh.isEmpty ? pool : fresh;
    final tip = list[rnd.nextInt(list.length)];

    final entrance = pose == GuaraPoseHint.sleep
        ? IntroEntrance.peek
        : IntroEntrance.values[rnd.nextInt(IntroEntrance.values.length)];
    return IntroMessage(title: title, text: text, tip: tip, tipIsAdvice: advice, pose: pose, entrance: entrance);
  }
}
