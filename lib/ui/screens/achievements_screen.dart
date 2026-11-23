import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../domain/achievements.dart';
import '../../state/app_state.dart';
import '../widgets/achievement_widgets.dart';
import '../widgets/common.dart';
import '../widgets/guara.dart';
import '../widgets/pace_ui.dart';
import 'activity_detail_screen.dart';

/// Conquistas: medalhas por grupo, com progresso das que faltam.
class AchievementsScreen extends StatelessWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final all = app.badges;
    final got = all.where((b) => b.unlocked).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Conquistas')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          GlassCard(
            child: Row(
              children: [
                ProgressRing(
                  progress: all.isEmpty ? 0 : got / all.length,
                  size: 76,
                  stroke: 8,
                  color: PaceColors.mintBright,
                  track: Colors.white.withValues(alpha: 0.12),
                  center: Text('$got', style: numStyle(24, color: Colors.white)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$got de ${all.length} medalhas', style: numStyle(20, color: Colors.white)),
                      const SizedBox(height: 4),
                      Text(
                        got == all.length ? 'Coleção completa. Lenda!' : 'Toque numa medalha para ver o que falta.',
                        style: TextStyle(color: const Pal(true).muted),
                      ),
                    ],
                  ),
                ),
                const Guara(pose: GuaraPose.celebrate, size: 64),
              ],
            ),
          ),
          for (final g in BadgeGroup.values) ...[
            SectionTitle(g.label),
            GlassCard(
              padding: const EdgeInsets.fromLTRB(8, 14, 8, 6),
              child: LayoutBuilder(builder: (context, c) {
                final items = all.where((b) => b.group == g).toList();
                final cols = c.maxWidth > 420 ? 4 : 3;
                final w = c.maxWidth / cols;
                return Wrap(
                  children: [
                    for (final b in items)
                      SizedBox(
                        width: w,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => _details(context, b),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
                            child: Column(
                              children: [
                                BadgeMedal(badge: b, size: 62),
                                const SizedBox(height: 6),
                                Text(
                                  b.title,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.2,
                                    fontWeight: FontWeight.w700,
                                    color: b.unlocked ? Colors.white : const Pal(true).muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              }),
            ),
          ],
        ],
      ),
    );
  }

  static void _details(BuildContext context, Achievement b) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              BadgeMedal(badge: b, size: 96),
              const SizedBox(height: 12),
              Text(b.title, style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(b.description, textAlign: TextAlign.center),
              const SizedBox(height: 14),
              if (b.unlocked)
                Pill(
                  text: 'Conquistada em ${Fmt.date(b.unlockedAt!)}',
                  bg: PaceColors.mint.withValues(alpha: 0.14),
                  fg: PaceColors.mintDark,
                  icon: Icons.check_rounded,
                )
              else ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(value: b.progress, minHeight: 8),
                ),
                const SizedBox(height: 6),
                Text(b.progressText ?? 'Ainda não conquistada', style: TextStyle(color: Pal.of(ctx).muted)),
              ],
              if (b.unlocked && b.activityId != null) ...[
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => ActivityDetailScreen(activityId: b.activityId!)));
                  },
                  icon: const Icon(Icons.directions_run),
                  label: const Text('Ver a corrida'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
