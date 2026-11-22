import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../domain/models.dart';
import '../../domain/stats.dart';
import '../../state/app_state.dart';
import '../shell.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/pace_ui.dart';
import '../widgets/route_widgets.dart';
import 'activity_detail_screen.dart';
import 'import_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = Pal.of(context);
    final now = DateTime.now();
    final prof = app.profile;
    final first = prof.name.trim().split(' ').first;
    final last = app.activities.isEmpty ? null : app.activities.first;

    return Scaffold(
      body: Stack(
        children: [
          if (last != null) Positioned(top: 90, left: 0, right: 0, child: RouteBackground(points: last.previewPoints, height: 600)),
          SafeArea(
            bottom: false,
            child: RefreshIndicator(
              color: p.mint,
              onRefresh: app.reload,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 130),
                children: [
                  Appear(
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(Fmt.weekdayDate(now.toUtc()),
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.muted)),
                              const SizedBox(height: 2),
                              Text('${_greeting(now)}, $first', style: numStyle(28, color: p.ink)),
                            ],
                          ),
                        ),
                        Semantics(
                          button: true,
                          label: 'Perfil',
                          child: GestureDetector(
                            onTap: () => HomeShell.of(context)?.go(4),
                            child: Container(
                              width: 44,
                              height: 44,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(15),
                                gradient: const LinearGradient(colors: [PaceColors.mint, PaceColors.mintDark]),
                              ),
                              child: Text(prof.initials, style: numStyle(16, color: Colors.white)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (last == null)
                    Appear(delayMs: 80, child: _EmptyHome())
                  else ...[
                    Appear(delayMs: 80, child: _GoalCard(app: app, now: now)),
                    const SizedBox(height: 12),
                    Appear(delayMs: 160, child: _TodayRow(stats: app.dayStats(now), last: last, now: now)),
                    const SizedBox(height: 12),
                    Appear(
                      delayMs: 240,
                      child: _LastRunCard(
                        a: last,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => ActivityDetailScreen(activityId: last.id!)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Appear(delayMs: 320, child: _Last7(activities: app.activities, now: now)),
                    ..._insights(context, app, now).map((w) => Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Appear(delayMs: 400, child: w),
                        )),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _greeting(DateTime now) {
    if (now.hour < 12) return 'Bom dia';
    if (now.hour < 18) return 'Boa tarde';
    return 'Boa noite';
  }

  /// Observação só quando há algo concreto a dizer (nada inventado).
  static List<Widget> _insights(BuildContext context, AppState app, DateTime now) {
    final out = <String>[];
    final week = app.weekStats(now);
    final goal = app.profile.weeklyGoalKm;
    final left = goal - week.distanceM / 1000;
    final last = app.activities.first;
    if (app.activities.length > 1 && last.distanceM >= app.lifetime.longestM - 0.5) {
      out.add('Sua última corrida foi a mais longa até hoje: ${Fmt.kmUnit(last.distanceM)}.');
    } else if (week.count > 0 && left > 0) {
      out.add('${week.count == 1 ? 'Primeira corrida' : '${week.count}ª corrida'} da semana feita. '
          'Faltam ${Fmt.kmUnit(left * 1000, decimals: 1)} para a meta.');
    } else if (week.count > 0 && left <= 0) {
      out.add('Meta da semana cumprida com ${Fmt.kmUnit(week.distanceM, decimals: 1)}. Lembre de reservar um dia de descanso.');
    }
    final days = DateTime.now().toUtc().difference(last.start).inDays;
    if (days >= 7) out.add('Sua última corrida foi há $days dias. Que tal uma rodagem leve hoje?');
    if (out.isEmpty) return const [];
    final p = Pal.of(context);
    return [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: p.dark
                ? [const Color(0x2E12B886), const Color(0x2E6D4AE0)]
                : [const Color(0xFFE3F7EF), const Color(0xFFEEE9FE)],
          ),
        ),
        child: Column(
          children: [
            for (var i = 0; i < out.length; i++)
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(12)),
                      child: Icon(Icons.trending_up_rounded, color: p.mintText, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(out[i], style: TextStyle(fontSize: 14, height: 1.35, color: p.ink))),
                  ],
                ),
              ),
          ],
        ),
      ),
    ];
  }
}

class _EmptyHome extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: EmptyState(
        icon: Icons.directions_run_rounded,
        title: 'Sua primeira corrida começa aqui',
        message: 'Grave uma corrida com o GPS ou importe seu histórico de outros apps (.tcx ou .gpx).',
        actions: [
          FilledButton.icon(
            onPressed: () => HomeShell.of(context)?.go(2),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Correr agora'),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ImportScreen())),
            icon: const Icon(Icons.upload_file),
            label: const Text('Importar histórico'),
          ),
        ],
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  final AppState app;
  final DateTime now;
  const _GoalCard({required this.app, required this.now});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final week = app.weekStats(now);
    final goal = app.profile.weeklyGoalKm;
    final km = week.distanceM / 1000;
    final ratio = goal > 0 ? km / goal : 0.0;
    final done = ratio >= 1;
    final left = (goal - km).clamp(0.0, double.infinity);
    final prev = app.lastWeekSameSpan(now);
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          ProgressRing(
            progress: ratio,
            size: 124,
            stroke: 13,
            color: p.mint,
            track: p.mintSoft,
            center: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CountUp(
                  value: (ratio * 100).clamp(0, 999).toDouble(),
                  format: (v) => '${v.round()}%',
                  style: numStyle(28, color: p.ink, height: 1),
                ),
                Text('da meta', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: p.muted)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('META DA SEMANA',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1, color: p.muted)),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      CountUp(
                        value: km,
                        format: (v) => Fmt.km(v * 1000, decimals: 1),
                        style: numStyle(38, color: p.ink, height: 1),
                      ),
                      Text(' / ${Fmt.integer(goal)} km',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.muted)),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Pill(
                  text: done ? 'Meta cumprida!' : 'Faltam ${Fmt.kmUnit(left * 1000, decimals: 1)}',
                  bg: p.mintSoft,
                  fg: p.mintText,
                  icon: done ? Icons.emoji_events_rounded : Icons.flag_rounded,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        '${week.count} ${week.count == 1 ? 'corrida' : 'corridas'} · ${Fmt.durationLong(week.movingSec)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: p.muted, fontWeight: FontWeight.w500),
                      ),
                    ),
                    const SizedBox(width: 6),
                    ChangeBadge(ratio: Periods.change(week.distanceM, prev.distanceM)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayRow extends StatelessWidget {
  final PeriodStats stats;
  final Activity last;
  final DateTime now;
  const _TodayRow({required this.stats, required this.last, required this.now});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    // Hoje, se correu hoje; senão, os números da última corrida.
    final today = stats.count > 0;
    final sec = today ? stats.movingSec.toDouble() : last.movingSec.toDouble();
    final pace = today ? stats.avgPace : last.paceSecPerKm;
    final kcal = today ? stats.calories : (last.calories ?? 0);
    final suffix = today ? 'hoje' : 'última';
    return Row(
      children: [
        Expanded(
          child: MetricCard(
            icon: Icons.timer_outlined,
            color: p.violet,
            soft: p.violetSoft,
            value: CountUp(value: sec, format: Fmt.duration, style: numStyle(22, color: p.ink)),
            label: 'Tempo $suffix',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: MetricCard(
            icon: Icons.bolt_rounded,
            color: p.orange,
            soft: p.orangeSoft,
            value: CountUp(value: pace ?? 0, format: (v) => Fmt.pace(v <= 0 ? null : v), style: numStyle(22, color: p.ink)),
            label: 'Pace /km',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: MetricCard(
            icon: Icons.local_fire_department_outlined,
            color: p.pink,
            soft: p.pinkSoft,
            value: CountUp(value: kcal, format: (v) => Fmt.integer(v), style: numStyle(22, color: p.ink)),
            label: 'kcal (estim.)',
          ),
        ),
      ],
    );
  }
}

class _LastRunCard extends StatelessWidget {
  final Activity a;
  final VoidCallback onTap;
  const _LastRunCard({required this.a, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final isToday = Periods.dayStart(a.start.toLocal()) == Periods.dayStart(DateTime.now());
    final when = isToday ? 'Hoje, ${Fmt.time(a.start)}' : '${Fmt.date(a.start)} · ${Fmt.time(a.start)}';
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          RouteThumbnail(points: a.previewPoints, size: 88, strokeWidth: 3.5),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$when · ${a.type}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.muted)),
                const SizedBox(height: 4),
                Text(Fmt.kmUnit(a.distanceM), style: numStyle(26, color: p.ink)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 12,
                  children: [
                    _kv(context, Fmt.duration(a.movingSec), 'tempo'),
                    _kv(context, Fmt.pace(a.paceSecPerKm), '/km'),
                  ],
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: p.muted),
        ],
      ),
    );
  }

  Widget _kv(BuildContext context, String v, String l) {
    final p = Pal.of(context);
    return Text.rich(TextSpan(children: [
      TextSpan(text: v, style: numStyle(14, color: p.ink)),
      TextSpan(text: ' $l', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: p.muted)),
    ]));
  }
}

class _Last7 extends StatelessWidget {
  final List<Activity> activities;
  final DateTime now;
  const _Last7({required this.activities, required this.now});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final today = Periods.dayStart(now);
    final from = today.subtract(const Duration(days: 6));
    final to = DateTime(today.year, today.month, today.day + 1);
    final b = kmBuckets(activities, from, to, Bucket.day);
    final total = b.fold<double>(0, (s, e) => s + e.km);
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Últimos 7 dias', style: numStyle(17, color: p.ink))),
              Text('${Fmt.km(total * 1000, decimals: 1)} km',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.muted)),
            ],
          ),
          const SizedBox(height: 12),
          KmBarChart(
            data: [for (final x in b) (label: Fmt.weekdayShort(x.start), km: x.km)],
            highlightIndex: b.length - 1,
            height: 150,
          ),
        ],
      ),
    );
  }
}
