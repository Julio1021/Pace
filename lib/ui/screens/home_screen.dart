import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../domain/coach.dart';
import '../../domain/models.dart';
import '../../domain/stats.dart';
import '../../state/app_state.dart';
import '../shell.dart';
import '../widgets/charts.dart';
import '../widgets/guara.dart';
import '../widgets/common.dart';
import '../widgets/pace_ui.dart';
import '../widgets/route_widgets.dart';
import 'activity_detail_screen.dart';
import 'import_screen.dart';
import 'plans_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  /// Permite fixar o horário nas prints de teste.
  static DateTime Function() clock = DateTime.now;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = Pal.of(context);
    final now = clock();
    final prof = app.profile;
    final first = prof.name.trim().split(' ').first;
    final last = app.activities.isEmpty ? null : app.activities.first;

    return Scaffold(
      body: Stack(
        children: [
          const Positioned(top: 0, left: 0, right: 0, child: MeshBackground(height: 720)),
          SafeArea(
            bottom: false,
            child: RefreshIndicator(
              color: p.mint,
              onRefresh: app.reload,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 130),
                children: [
                  if (last == null) ...[
                    Appear(
                      child: _Header(date: Fmt.weekdayDate(now.toUtc()), greeting: '${_greeting(now)}, $first'),
                    ),
                    const SizedBox(height: 16),
                    Appear(delayMs: 80, child: _EmptyHome()),
                  ] else ...[
                    Appear(
                      child: _HomeTop(
                        date: Fmt.weekdayDate(now.toUtc()),
                        greeting: '${_greeting(now)}, $first',
                        mood: _GuaraMood.of(app, now, first),
                        card: _GoalCard(app: app, now: now),
                      ),
                    ),
                    if (app.plan?.plan != null && !app.plan!.finished) ...[
                      const SizedBox(height: 12),
                      Appear(
                        delayMs: 120,
                        child: PlanProgressCard(
                          active: app.plan!,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => PlanDetailScreen(plan: app.plan!.plan!)),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Appear(delayMs: 160, child: _TodayRow(stats: app.dayStats(now), last: last, now: now)),
                    const SizedBox(height: 12),
                    Appear(
                      delayMs: 240,
                      child: Builder(builder: (context) {
                        // O treino mais recente, seja corrida ou pedal.
                        final recent = app.allActivities.first;
                        return _LastRunCard(
                          a: recent,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => ActivityDetailScreen(activityId: recent.id!)),
                          ),
                        );
                      }),
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
    final days = now.toUtc().difference(last.start).inDays;
    if (days >= 7) out.add('Sua última corrida foi há $days dias. Que tal uma rodagem leve hoje?');
    if (out.isEmpty) return const [];
    final p = Pal.of(context);
    final rest = week.count > 0 && left <= 0;
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
                    if (i == 0 && rest)
                      const Guara(pose: GuaraPose.sleep, size: 64)
                    else
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

/// Data e saudação no topo.
class _Header extends StatelessWidget {
  final String date;
  final String greeting;
  final double rightGap;
  const _Header({required this.date, required this.greeting, this.rightGap = 0});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Padding(
      padding: EdgeInsets.only(right: rightGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(date, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.muted)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(greeting, style: numStyle(28, color: p.ink)),
          ),
        ],
      ),
    );
  }
}

/// Como o Guará está agora, e o que ele diz quando é tocado.
class _GuaraMood {
  final GuaraPose pose;
  final List<String> lines;
  final bool callsToRun;
  const _GuaraMood(this.pose, this.lines, {this.callsToRun = false});

  static _GuaraMood of(AppState app, DateTime now, String first) {
    final h = now.hour;
    final goal = app.profile.weeklyGoalKm;
    final week = app.weekStats(now);
    final met = goal > 0 && week.distanceM / 1000 >= goal;
    final last = app.activities.isEmpty ? null : app.activities.first;
    final days = last == null ? 0 : now.toUtc().difference(last.start).inDays;
    final name = first.isEmpty ? '' : ', $first';
    if (h >= 22 || h < 5) {
      return const _GuaraMood(GuaraPose.sleep, [
        'Zzz… descanso também é treino.',
        'Amanhã a gente corre!',
        'Dormir bem deixa o pace mais leve.',
      ]);
    }
    if (met) {
      return const _GuaraMood(GuaraPose.celebrate, [
        'Meta da semana batida! Que semana!',
        'Você mandou muito bem.',
        'Agora é manter o ritmo, sem exagero.',
      ]);
    }
    if (days >= 3) {
      return _GuaraMood(
        GuaraPose.run,
        ['$days dias sem correr… bora?', 'Só 20 minutinhos já valem!', 'Seu tênis está com saudade.'],
        callsToRun: true,
      );
    }
    return _GuaraMood(GuaraPose.wave, [
      'Oi$name! Bora correr hoje?',
      ...CoachPhrases.daily.take(6),
    ]);
  }
}

/// Topo da tela Início: saudação, card da meta e o Guará sentado em cima do card.
class _HomeTop extends StatefulWidget {
  final String date;
  final String greeting;
  final _GuaraMood mood;
  final Widget card;
  const _HomeTop({required this.date, required this.greeting, required this.mood, required this.card});

  @override
  State<_HomeTop> createState() => _HomeTopState();
}

class _HomeTopState extends State<_HomeTop> with SingleTickerProviderStateMixin {
  static const _headerH = 66.0;
  static const _gap = 16.0;
  static const _size = 78.0;

  late final AnimationController _jump = AnimationController(vsync: this, duration: const Duration(milliseconds: 620));
  String? _line;
  int _next = 0;
  int _waveTick = 0;
  Timer? _hide;

  @override
  void dispose() {
    _jump.dispose();
    _hide?.cancel();
    super.dispose();
  }

  void _tap() {
    HapticFeedback.selectionClick();
    final lines = widget.mood.lines;
    setState(() {
      _line = lines[_next++ % lines.length];
      _waveTick++;
    });
    if (motionOn(context)) _jump.forward(from: 0);
    _hide?.cancel();
    _hide = Timer(const Duration(milliseconds: 3200), () {
      if (mounted) setState(() => _line = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final mood = widget.mood;
    // Onde ficam os pés em cada desenho (fração da altura), para ele "sentar" no card.
    final feet = switch (mood.pose) {
      GuaraPose.sleep => 0.93,
      GuaraPose.run => 0.9,
      _ => 0.93,
    };
    final h = _size * 170 / 160;
    final top = _headerH + _gap - h * feet;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: _headerH,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _Header(date: widget.date, greeting: widget.greeting, rightGap: _size + 12),
              ),
            ),
            const SizedBox(height: _gap),
            widget.card,
          ],
        ),
        Positioned(
          right: 14,
          top: top,
          child: Semantics(
            button: true,
            label: 'Guará, toque para uma mensagem',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _tap,
              child: AnimatedBuilder(
                animation: _jump,
                builder: (context, child) {
                  final v = _jump.value;
                  final up = v < 0.6 ? math.sin(v / 0.6 * math.pi) * 16 : math.sin((v - 0.6) / 0.4 * math.pi) * 3;
                  return Transform.translate(offset: Offset(0, -up), child: child);
                },
                child: Guara(
                  key: ValueKey(mood.pose),
                  pose: mood.pose,
                  size: _size,
                  waves: 3,
                  waveTrigger: _waveTick,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: _size + 18,
          top: 2,
          child: IgnorePointer(
            ignoring: _line == null,
            child: AnimatedOpacity(
              opacity: _line == null ? 0 : 1,
              duration: const Duration(milliseconds: 220),
              child: AnimatedSlide(
                offset: _line == null ? const Offset(0.05, 0.15) : Offset.zero,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutBack,
                child: GestureDetector(
                  onTap: mood.callsToRun ? () => HomeShell.of(context)?.go(2) : null,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 200),
                    padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                        bottomLeft: Radius.circular(16),
                        bottomRight: Radius.circular(4),
                      ),
                      boxShadow: const [BoxShadow(color: Color(0x260F172A), blurRadius: 16, offset: Offset(0, 6))],
                      border: Border.all(color: const Color(0x140F172A)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_line ?? '',
                            style: const TextStyle(fontSize: 13.5, height: 1.3, color: PaceColors.ink, fontWeight: FontWeight.w600)),
                        if (mood.callsToRun) ...[
                          const SizedBox(height: 4),
                          const Text('Correr agora ›',
                              style: TextStyle(fontSize: 12.5, color: PaceColors.mintDark, fontWeight: FontWeight.w800)),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyHome extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: EmptyState(
        icon: Icons.directions_run_rounded,
        art: const Guara(pose: GuaraPose.run, size: 150),
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
          TextButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PlansScreen())),
            icon: const Icon(Icons.event_note_rounded),
            label: const Text('Seguir um plano de treino'),
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
    const p = Pal(true);
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
    const p = Pal(true);
    // Hoje, se correu hoje; senão, os números da última corrida.
    final today = stats.count > 0;
    final sec = today ? stats.movingSec.toDouble() : last.movingSec.toDouble();
    final pace = today ? stats.avgPace : last.paceSecPerKm;
    final kcal = today ? stats.calories : (last.calories ?? 0);
    final suffix = today ? 'hoje' : '(última)';
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
    const p = Pal(true);
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
                Text('$when · ${a.isBike ? 'Pedal · ' : ''}${a.type}',
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
                    a.isBike ? _kv(context, Fmt.kmh(a.kmh), 'km/h') : _kv(context, Fmt.pace(a.paceSecPerKm), '/km'),
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
    const p = Pal(true);
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
    const p = Pal(true);
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
