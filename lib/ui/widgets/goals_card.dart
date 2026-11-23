import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../domain/goals.dart';
import '../../state/app_state.dart';
import 'pace_ui.dart';

/// Metas da semana, do mês e do ano, com previsão no ritmo atual.
class GoalsCard extends StatelessWidget {
  const GoalsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final now = DateTime.now();
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
      child: Column(
        children: [
          for (final (i, p) in GoalPeriod.values.indexed) ...[
            if (i > 0) const Divider(height: 18),
            _GoalRow(g: app.goal(p, now)),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => editGoals(context),
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: const Text('Ajustar metas'),
            ),
          ),
        ],
      ),
    );
  }
}

class _GoalRow extends StatelessWidget {
  final GoalStatus g;
  const _GoalRow({required this.g});

  @override
  Widget build(BuildContext context) {
    const p = Pal(true);
    final off = g.targetKm <= 0;
    String hint;
    Color hintColor = p.muted;
    if (off) {
      hint = 'Sem meta. ${Fmt.kmUnit(g.doneKm * 1000, decimals: 1)} até agora.';
    } else if (g.done) {
      hint = 'Meta batida! ${g.progress >= 1.2 ? 'E com sobra.' : ''}';
      hintColor = PaceColors.mintBright;
    } else {
      final parts = <String>['Faltam ${Fmt.km(g.leftKm * 1000, decimals: 1)} km'];
      final proj = g.projectedKm;
      if (g.period != GoalPeriod.week && g.neededPerWeek != null) {
        parts.add('${Fmt.integer(g.neededPerWeek!)} km/sem.');
      }
      if (proj != null) {
        final ok = proj >= g.targetKm * 0.98;
        parts.add('previsão ~${Fmt.integer(proj)} km');
        hintColor = ok ? PaceColors.mintBright : const Color(0xFFFFB37A);
      }
      hint = parts.join(' · ');
    }
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              SizedBox(
                width: 64,
                child: Text(g.period.label, style: TextStyle(fontWeight: FontWeight.w800, color: p.muted, fontSize: 13)),
              ),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: Fmt.km(g.doneKm * 1000, decimals: 1), style: numStyle(20, color: Colors.white)),
                    if (!off)
                      TextSpan(
                        text: ' / ${Fmt.integer(g.targetKm)} km',
                        style: TextStyle(color: p.muted, fontWeight: FontWeight.w700),
                      )
                    else
                      TextSpan(text: ' km', style: TextStyle(color: p.muted, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
              if (!off) Text(Fmt.percent(g.progress.clamp(0, 9.99)), style: numStyle(14, color: p.muted)),
            ],
          ),
          if (!off) ...[
            const SizedBox(height: 6),
            LayoutBuilder(builder: (context, c) {
              final ideal = g.elapsed.clamp(0.0, 1.0);
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: LinearProgressIndicator(
                      value: g.progress.clamp(0.0, 1.0),
                      minHeight: 8,
                      color: g.done ? PaceColors.mintBright : PaceColors.mint,
                      backgroundColor: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  // Marca de onde você "deveria" estar hoje.
                  if (!g.done && ideal > 0.02 && ideal < 0.98)
                    Positioned(
                      left: c.maxWidth * ideal - 1,
                      top: -2,
                      child: Container(width: 2, height: 12, color: Colors.white.withValues(alpha: 0.55)),
                    ),
                ],
              );
            }),
          ],
          const SizedBox(height: 5),
          Text(hint, style: TextStyle(fontSize: 12, color: hintColor, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Folha para ajustar as metas (semana, mês e ano).
Future<void> editGoals(BuildContext context) async {
  final app = context.read<AppState>();
  var w = app.profile.weeklyGoalKm;
  var m = app.profile.monthlyGoalKm;
  var y = app.profile.yearlyGoalKm;
  final saved = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        Widget row(String label, String hint, double v, double step, double max, void Function(double) on) => ListTile(
              title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(hint),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(onPressed: v <= 0 ? null : () => set(() => on((v - step).clamp(0, max))), icon: const Icon(Icons.remove_circle_outline)),
                  SizedBox(
                    width: 76,
                    child: Text(v <= 0 ? 'sem meta' : '${Fmt.integer(v)} km',
                        textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  ),
                  IconButton(onPressed: v >= max ? null : () => set(() => on((v + step).clamp(0, max))), icon: const Icon(Icons.add_circle_outline)),
                ],
              ),
            );
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text('Metas de quilometragem', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                ),
                row('Semana', 'Aparece no Início e no botão Iniciar', w, 1, 200, (v) => w = v),
                row('Mês', 'Ex.: 80 km', m, 5, 800, (v) => m = v),
                row('Ano', 'Ex.: 1.000 km', y, 50, 8000, (v) => y = v),
                if (w > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        ActionChip(
                          label: Text('Mês = ${Fmt.integer(w * 4.3)} km'),
                          onPressed: () => set(() => m = (w * 4.3 / 5).round() * 5.0),
                        ),
                        ActionChip(
                          label: Text('Ano = ${Fmt.integer(w * 52)} km'),
                          onPressed: () => set(() => y = (w * 52 / 50).round() * 50.0),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salvar')),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
  if (saved == true) {
    await app.saveProfile(app.profile.copyWith(weeklyGoalKm: w, monthlyGoalKm: m, yearlyGoalKm: y));
  }
}
