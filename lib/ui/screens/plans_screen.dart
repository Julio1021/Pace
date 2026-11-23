import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../domain/plans.dart';
import '../../state/app_state.dart';
import '../shell.dart';
import '../widgets/common.dart';
import '../widgets/guara.dart';
import '../widgets/pace_ui.dart';

/// Lista de planos de treino e o plano em andamento.
class PlansScreen extends StatelessWidget {
  const PlansScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final active = app.plan;
    return Scaffold(
      appBar: AppBar(title: const Text('Planos de treino')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          if (active?.plan != null) ...[
            const SectionTitle('Em andamento'),
            PlanProgressCard(active: active!, onTap: () => _open(context, active.plan!)),
            const SectionTitle('Outros planos'),
          ] else
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  const Guara(pose: GuaraPose.run, size: 70),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Escolha um objetivo. O PACE monta a semana, carrega o treino na tela Correr '
                      'e marca como feito sozinho quando você completa.',
                      style: TextStyle(color: Pal.of(context).muted, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          for (final p in TrainingPlan.all)
            if (p.id != active?.planId)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: GlassCard(
                  onTap: () => _open(context, p),
                  child: Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: PaceColors.mintBright.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.event_note_rounded, color: PaceColors.mintBright),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.name, style: numStyle(18, color: Colors.white)),
                            const SizedBox(height: 2),
                            Text('${p.level} · ${p.summary}', style: TextStyle(color: const Pal(true).muted, fontSize: 13)),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: const Pal(true).muted),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }

  static void _open(BuildContext context, TrainingPlan p) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => PlanDetailScreen(plan: p)));
}

/// Cartão com o progresso do plano e o próximo treino (usado também no Início).
class PlanProgressCard extends StatelessWidget {
  final ActivePlan active;
  final VoidCallback? onTap;
  final bool showStart;
  const PlanProgressCard({super.key, required this.active, this.onTap, this.showStart = true});

  @override
  Widget build(BuildContext context) {
    final plan = active.plan!;
    final next = active.nextIndex;
    final s = next == null ? null : plan.sessions[next];
    final total = plan.sessions.length;
    final done = active.done.length;
    const p = Pal(true);
    return GlassCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(plan.name.toUpperCase(),
                    style: TextStyle(fontSize: 12, letterSpacing: 1.2, fontWeight: FontWeight.w800, color: p.muted)),
              ),
              Text('$done/$total treinos', style: TextStyle(fontSize: 12, color: p.muted, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : done / total,
              minHeight: 6,
              color: PaceColors.mintBright,
              backgroundColor: Colors.white.withValues(alpha: 0.1),
            ),
          ),
          const SizedBox(height: 14),
          if (s == null)
            Row(
              children: [
                const Guara(pose: GuaraPose.celebrate, size: 56),
                const SizedBox(width: 10),
                Expanded(child: Text('Plano concluído! Você foi até o fim.', style: numStyle(17, color: Colors.white))),
              ],
            )
          else ...[
            Text('Próximo treino · Semana ${s.week}, treino ${s.n}', style: TextStyle(fontSize: 12.5, color: p.muted)),
            const SizedBox(height: 2),
            Text(s.title, style: numStyle(20, color: Colors.white)),
            const SizedBox(height: 4),
            Text(s.detail, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), height: 1.35)),
            if (active.weekNow(DateTime.now()) > s.week + 1) ...[
              const SizedBox(height: 6),
              Text('Você está um pouco atrás do calendário. Tudo bem: siga no seu ritmo.',
                  style: TextStyle(fontSize: 12, color: PaceColors.orange.withValues(alpha: 0.9))),
            ],
            if (showStart) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => startSession(context, next!),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Fazer este treino'),
              ),
            ],
          ],
        ],
      ),
    );
  }

  /// Carrega o treino na tela Correr.
  static void startSession(BuildContext context, int index) {
    context.read<AppState>().usePlanSession(index);
    Navigator.of(context).popUntil((r) => r.isFirst);
    HomeShell.of(context)?.go(2);
  }
}

/// Detalhes de um plano: semanas, treinos, começar/encerrar, marcar feito.
class PlanDetailScreen extends StatelessWidget {
  final TrainingPlan plan;
  const PlanDetailScreen({super.key, required this.plan});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final active = app.plan?.planId == plan.id ? app.plan : null;
    final next = active?.nextIndex;
    final weeks = <int, List<(int, PlanSession)>>{};
    for (final (i, s) in plan.sessions.indexed) {
      weeks.putIfAbsent(s.week, () => []).add((i, s));
    }
    return Scaffold(
      appBar: AppBar(title: Text(plan.name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          Text('${plan.level} · ${plan.summary}', style: TextStyle(color: Pal.of(context).muted, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(plan.forWho, style: const TextStyle(height: 1.4)),
          const SizedBox(height: 14),
          if (active == null)
            FilledButton.icon(
              onPressed: () => _start(context),
              icon: const Icon(Icons.flag_rounded),
              label: const Text('Começar este plano'),
            )
          else ...[
            PlanProgressCard(active: active),
            const SizedBox(height: 8),
            Text('Começou em ${Fmt.dayMonth(active.start)} · semana ${active.weekNow(DateTime.now())} do calendário',
                style: TextStyle(fontSize: 12.5, color: Pal.of(context).muted)),
          ],
          for (final w in weeks.entries) ...[
            SectionTitle('Semana ${w.key}'),
            GlassCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  for (final (k, (i, s)) in w.value.indexed) ...[
                    if (k > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                    ListTile(
                      leading: active == null
                          ? CircleAvatar(
                              radius: 15,
                              backgroundColor: Colors.white.withValues(alpha: 0.08),
                              child: Text('${s.n}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                            )
                          : IconButton(
                              tooltip: active.done.containsKey(i) ? 'Desmarcar' : 'Marcar como feito',
                              onPressed: () => app.toggleSession(i),
                              icon: Icon(
                                active.done.containsKey(i) ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                                color: active.done.containsKey(i) ? PaceColors.mintBright : const Pal(true).muted,
                              ),
                            ),
                      title: Text(s.title,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            decoration: active?.done.containsKey(i) == true ? TextDecoration.lineThrough : null,
                          )),
                      subtitle: Text(s.detail, style: TextStyle(color: const Pal(true).muted, fontSize: 12.5)),
                      trailing: i == next
                          ? IconButton.filled(
                              tooltip: 'Fazer este treino',
                              onPressed: () => PlanProgressCard.startSession(context, i),
                              icon: const Icon(Icons.play_arrow_rounded),
                            )
                          : null,
                    ),
                  ],
                ],
              ),
            ),
          ],
          if (active != null) ...[
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () => _stop(context),
              icon: const Icon(Icons.close_rounded),
              label: const Text('Encerrar plano'),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            'Uma corrida conta para o próximo treino quando chega a 80% do alvo. '
            'Você também pode marcar ou desmarcar à mão.',
            style: TextStyle(fontSize: 12, color: Pal.of(context).muted),
          ),
        ],
      ),
    );
  }

  Future<void> _start(BuildContext context) async {
    final app = context.read<AppState>();
    if (app.plan != null) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Trocar de plano?'),
          content: Text('O plano "${app.plan!.plan?.name}" será encerrado e o progresso dele será perdido.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Trocar')),
          ],
        ),
      );
      if (ok != true) return;
    }
    await app.startPlan(plan.id, DateTime.now());
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Plano iniciado. Bora!')));
    }
  }

  Future<void> _stop(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Encerrar plano?'),
        content: const Text('Suas corridas continuam salvas; só o acompanhamento do plano é removido.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Encerrar')),
        ],
      ),
    );
    if (ok == true && context.mounted) await context.read<AppState>().stopPlan();
  }
}
