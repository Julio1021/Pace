import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../domain/models.dart';
import '../../domain/stats.dart';
import '../../state/app_state.dart';
import '../shell.dart';
import '../widgets/activity_tile.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import 'activity_detail_screen.dart';
import 'import_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final now = DateTime.now();
    final p = app.profile;
    final first = p.name.trim().split(' ').first;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: app.reload,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${_greeting(now)}, $first!', style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text(Fmt.weekdayDate(now.toUtc()), style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => HomeShell.of(context)?.go(4),
                    child: CircleAvatar(
                      radius: 22,
                      backgroundColor: cs.primary,
                      child: Text(p.initials,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (app.activities.isEmpty)
                PaceCard(
                  child: EmptyState(
                    icon: Icons.directions_run,
                    title: 'Sua primeira corrida começa aqui',
                    message: 'Grave uma corrida com o GPS ou importe seu histórico de outros apps (arquivos .tcx ou .gpx).',
                    actions: [
                      FilledButton.icon(
                        onPressed: () => HomeShell.of(context)?.go(2),
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Correr agora'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ImportScreen())),
                        icon: const Icon(Icons.upload_file),
                        label: const Text('Importar histórico'),
                      ),
                    ],
                  ),
                )
              else ...[
                _TodayCard(stats: app.dayStats(now)),
                const SizedBox(height: 12),
                _WeekCard(app: app, now: now),
                const SectionTitle('Última corrida'),
                ActivityCard(
                  activity: app.activities.first,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => ActivityDetailScreen(activityId: app.activities.first.id!)),
                  ),
                ),
                const SectionTitle('Últimos 7 dias'),
                PaceCard(
                  padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
                  child: _Last7Chart(activities: app.activities, now: now),
                ),
                const SectionTitle('Observações'),
                _Insights(app: app, now: now),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _greeting(DateTime now) {
    if (now.hour < 12) return 'Bom dia';
    if (now.hour < 18) return 'Boa tarde';
    return 'Boa noite';
  }
}

class _TodayCard extends StatelessWidget {
  final PeriodStats stats;
  const _TodayCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return PaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Hoje', style: t.titleMedium),
          const SizedBox(height: 12),
          if (stats.count == 0)
            Text('Nenhuma corrida hoje ainda.', style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant))
          else
            StatGrid(columns: 3, children: [
              StatTile(label: 'Distância', value: Fmt.km(stats.distanceM), unit: 'km'),
              StatTile(label: 'Tempo', value: Fmt.duration(stats.movingSec)),
              StatTile(label: 'Pace médio', value: Fmt.pace(stats.avgPace), unit: '/km'),
              StatTile(label: 'Treinos', value: '${stats.count}'),
              StatTile(label: 'Calorias (estim.)', value: Fmt.integer(stats.calories), unit: 'kcal'),
            ]),
        ],
      ),
    );
  }
}

class _WeekCard extends StatelessWidget {
  final AppState app;
  final DateTime now;
  const _WeekCard({required this.app, required this.now});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final week = app.weekStats(now);
    final prev = app.lastWeekSameSpan(now);
    final goal = app.profile.weeklyGoalKm;
    final km = week.distanceM / 1000;
    final ratio = goal > 0 ? (km / goal) : 0.0;
    final done = ratio >= 1;
    return PaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Esta semana', style: t.titleMedium)),
              ChangeBadge(ratio: Periods.change(week.distanceM, prev.distanceM), suffix: ' km'),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(Fmt.km(week.distanceM, decimals: 1),
                  style: t.headlineLarge?.copyWith(fontWeight: FontWeight.w900, color: cs.primary)),
              const SizedBox(width: 6),
              Text('de ${Fmt.integer(goal)} km', style: t.titleMedium?.copyWith(color: cs.onSurfaceVariant)),
              const Spacer(),
              Text(done ? 'Meta cumprida!' : Fmt.percent(ratio.clamp(0.0, 1.0)),
                  style: t.titleMedium?.copyWith(color: done ? cs.secondary : cs.onSurface)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: ratio.clamp(0, 1).toDouble(),
              minHeight: 10,
              color: done ? cs.secondary : cs.primary,
              backgroundColor: cs.onSurface.withValues(alpha: 0.08),
            ),
          ),
          const SizedBox(height: 16),
          StatGrid(columns: 3, children: [
            StatTile(label: 'Corridas', value: '${week.count}'),
            StatTile(label: 'Tempo', value: Fmt.durationLong(week.movingSec)),
            StatTile(label: 'Pace médio', value: Fmt.pace(week.avgPace), unit: '/km'),
          ]),
          const SizedBox(height: 10),
          Text(
            prev.count == 0
                ? 'Sem corridas no mesmo período da semana passada.'
                : 'Mesmo período da semana passada: ${Fmt.kmUnit(prev.distanceM, decimals: 1)} em ${prev.count} '
                    '${prev.count == 1 ? 'corrida' : 'corridas'}.',
            style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _Last7Chart extends StatelessWidget {
  final List<Activity> activities;
  final DateTime now;
  const _Last7Chart({required this.activities, required this.now});

  @override
  Widget build(BuildContext context) {
    final today = Periods.dayStart(now);
    final from = today.subtract(const Duration(days: 6));
    final to = DateTime(today.year, today.month, today.day + 1);
    final buckets = kmBuckets(activities, from, to, Bucket.day);
    return KmBarChart(
      data: [for (final b in buckets) (label: Fmt.weekdayShort(b.start), km: b.km)],
      highlightIndex: buckets.length - 1,
      height: 150,
    );
  }
}

/// Observações tiradas só dos dados reais.
class _Insights extends StatelessWidget {
  final AppState app;
  final DateTime now;
  const _Insights({required this.app, required this.now});

  @override
  Widget build(BuildContext context) {
    final items = <({IconData icon, String text})>[];
    final monthStart = Periods.monthStart(now);
    final prevMonthStart = DateTime(now.year, now.month - 1);
    final dayOfMonth = now.difference(monthStart);
    final cur = PeriodStats.of(Periods.between(app.activities, monthStart, now.add(const Duration(minutes: 1))));
    final prevSpan = PeriodStats.of(Periods.between(app.activities, prevMonthStart, prevMonthStart.add(dayOfMonth)));
    final ch = Periods.change(cur.distanceM, prevSpan.distanceM);
    if (ch != null && cur.count > 0) {
      final pct = (ch * 100).round();
      items.add((
        icon: pct >= 0 ? Icons.trending_up : Icons.trending_down,
        text: pct >= 0
            ? 'Você correu $pct% mais km neste mês do que no mesmo período do mês passado.'
            : 'Você correu ${pct.abs()}% menos km neste mês do que no mesmo período do mês passado.',
      ));
    }
    final last = app.activities.first;
    final longest = app.lifetime.longestM;
    if (app.activities.length > 1 && last.distanceM >= longest - 0.5) {
      items.add((icon: Icons.emoji_events_outlined, text: 'Sua última corrida foi a mais longa: ${Fmt.kmUnit(last.distanceM)}.'));
    }
    final lastPace = last.paceSecPerKm;
    final best = app.lifetime.bestPace;
    if (app.activities.length > 1 && lastPace != null && best != null && last.distanceM >= 1000 && lastPace <= best + 0.5) {
      items.add((icon: Icons.bolt, text: 'Melhor pace médio até hoje na última corrida: ${Fmt.paceUnit(lastPace)}.'));
    }
    final days = DateTime.now().toUtc().difference(last.start).inDays;
    if (days >= 7) {
      items.add((icon: Icons.schedule, text: 'Sua última corrida foi há $days dias.'));
    }
    final cs = Theme.of(context).colorScheme;
    if (items.isEmpty) {
      return PaceCard(
        child: Text('Continue registrando corridas: as observações aparecem quando houver dados suficientes para comparar.',
            style: TextStyle(color: cs.onSurfaceVariant)),
      );
    }
    return PaceCard(
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(height: 20),
            Row(
              children: [
                Icon(items[i].icon, color: cs.primary),
                const SizedBox(width: 12),
                Expanded(child: Text(items[i].text)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
