import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../domain/models.dart';
import '../../domain/stats.dart';
import '../../state/app_state.dart';
import '../widgets/achievement_widgets.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/goals_card.dart';
import '../widgets/guara.dart';
import '../widgets/pace_ui.dart';
import 'achievements_screen.dart';
import 'plans_screen.dart';
import 'records_screen.dart';

enum EvoPeriod { d7, d30, d90, m12, year, all }

class EvolutionScreen extends StatefulWidget {
  const EvolutionScreen({super.key});

  @override
  State<EvolutionScreen> createState() => _EvolutionScreenState();
}

class _EvolutionScreenState extends State<EvolutionScreen> {
  EvoPeriod _p = EvoPeriod.d30;
  int _year = DateTime.now().year;
  Sport _sport = Sport.run;

  static const _labels = {
    EvoPeriod.d7: '7 dias',
    EvoPeriod.d30: '30 dias',
    EvoPeriod.d90: '90 dias',
    EvoPeriod.m12: '12 meses',
    EvoPeriod.year: 'Ano',
    EvoPeriod.all: 'Tudo',
  };

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (app.rides.isEmpty) _sport = Sport.run;
    final bike = _sport == Sport.bike;
    final acts = app.listFor(_sport);
    final life = PeriodStats.of(acts);
    final cs = glassTheme.colorScheme;
    final t = glassTheme.textTheme;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final end = today.add(const Duration(days: 1));

    DateTime start;
    var stop = end;
    DateTime? prevStart;
    Bucket bucket;
    switch (_p) {
      case EvoPeriod.d7:
        start = today.subtract(const Duration(days: 6));
        bucket = Bucket.day;
      case EvoPeriod.d30:
        start = today.subtract(const Duration(days: 29));
        bucket = Bucket.week;
      case EvoPeriod.d90:
        start = today.subtract(const Duration(days: 89));
        bucket = Bucket.week;
      case EvoPeriod.m12:
        start = DateTime(now.year - 1, now.month + 1);
        bucket = Bucket.month;
      case EvoPeriod.year:
        start = DateTime(_year);
        final yEnd = DateTime(_year + 1);
        stop = yEnd.isBefore(end) ? yEnd : end;
        prevStart = DateTime(_year - 1);
        bucket = Bucket.month;
      case EvoPeriod.all:
        final first = acts.isEmpty ? today : acts.last.start.toLocal();
        // Muitos anos: um ponto por ano; senão, por mês.
        final months = (now.year - first.year) * 12 + now.month - first.month + 1;
        bucket = months > 30 ? Bucket.year : Bucket.month;
        start = bucket == Bucket.year ? DateTime(first.year) : DateTime(first.year, first.month);
    }
    final span = stop.difference(start);
    final cur = PeriodStats.of(Periods.between(acts, start, stop));
    final prev = _p == EvoPeriod.all
        ? null
        : _p == EvoPeriod.year
            // Ano anterior até o mesmo dia (comparação justa no ano em curso).
            ? PeriodStats.of(Periods.between(acts, prevStart!, DateTime(_year - 1, stop.month, stop.day)))
            : PeriodStats.of(Periods.between(acts, start.subtract(span), start));
    final buckets = kmBuckets(acts, start, bucket == Bucket.month && _p == EvoPeriod.year ? DateTime(_year + 1) : stop, bucket);
    final chartData = [
      for (final b in buckets)
        (
          label: switch (bucket) {
            Bucket.day => Fmt.weekdayShort(b.start),
            Bucket.week => Fmt.dayMonth(b.start),
            Bucket.month => buckets.length > 14 ? '${Fmt.monthShort(b.start)}/${b.start.year % 100}' : Fmt.monthShort(b.start),
            Bucket.year => '${b.start.year}',
          },
          km: b.km,
        ),
    ];
    final labelEvery = chartData.length <= 8 ? 1 : (chartData.length / 6).ceil();

    return Scaffold(
      body: Stack(
        children: [
          const Positioned(top: 0, left: 0, right: 0, child: MeshBackground(height: 560)),
          SafeArea(
            bottom: false,
            child: app.allActivities.isEmpty
          ? const Center(
              child: EmptyState(
                icon: Icons.insights,
                art: Guara(pose: GuaraPose.sleep, size: 150),
                title: 'Sem dados ainda',
                message: 'Grave ou importe corridas para acompanhar sua evolução.',
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 130),
              children: [
                const Appear(child: ScreenTitle('Evolução')),
                const SizedBox(height: 14),
                Appear(delayMs: 60, child: _Shortcuts(app: app)),
                const SectionTitle('Metas'),
                const Appear(delayMs: 120, child: GoalsCard()),
                SectionTitle(
                  'Seus números',
                  trailing: app.rides.isEmpty
                      ? null
                      : SegmentedButton<Sport>(
                          showSelectedIcon: false,
                          style: const ButtonStyle(visualDensity: VisualDensity.compact),
                          segments: const [
                            ButtonSegment(value: Sport.run, icon: Icon(Icons.directions_run_rounded, size: 18), label: Text('Corrida')),
                            ButtonSegment(value: Sport.bike, icon: Icon(Icons.directions_bike_rounded, size: 18), label: Text('Pedal')),
                          ],
                          selected: {_sport},
                          onSelectionChanged: (v) => setState(() => _sport = v.first),
                        ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final e in _labels.entries)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: e.key == EvoPeriod.year
                              ? _YearChip(
                                  years: _years(acts),
                                  selected: _p == EvoPeriod.year,
                                  year: _year,
                                  onPick: (y) => setState(() {
                                    _p = EvoPeriod.year;
                                    _year = y;
                                  }),
                                )
                              : ChoiceChip(
                                  label: Text(e.value),
                                  selected: _p == e.key,
                                  onSelected: (_) => setState(() => _p = e.key),
                                ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                PaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text('Distância total', style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                          ),
                          if (prev != null) ChangeBadge(ratio: Periods.change(cur.distanceM, prev.distanceM)),
                        ],
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text.rich(TextSpan(children: [
                          TextSpan(
                            text: Fmt.km(cur.distanceM, decimals: cur.distanceM >= 1000000 ? 0 : 1),
                            style: numStyle(40, color: cs.onSurface),
                          ),
                          TextSpan(text: ' km', style: numStyle(22, color: cs.onSurfaceVariant)),
                        ])),
                      ),
                      if (prev != null)
                        Text(
                          'Período anterior equivalente: ${Fmt.kmUnit(prev.distanceM, decimals: 1)}',
                          style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      const SizedBox(height: 16),
                      KmBarChart(data: chartData, labelEvery: labelEvery, height: 170),
                      const SizedBox(height: 4),
                      Center(
                        child: Text(
                          switch (bucket) {
                            Bucket.day => 'km por dia',
                            Bucket.week => 'km por semana (início na segunda)',
                            Bucket.month => 'km por mês',
                            Bucket.year => 'km por ano',
                          },
                          style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ),
                SectionTitle(bike ? 'Seu ano no pedal' : 'Seu ano em corridas'),
                PaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      YearMosaic(kmByDay: _kmByDay(acts), today: now, weeks: 26),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Text('Últimos 6 meses · cada quadrado é um dia',
                                style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                          ),
                          Text('menos ', style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                          for (final c in [const Pal(true).faint, const Pal(true).mintMid, const Pal(true).mint])
                            Container(
                              width: 10,
                              height: 10,
                              margin: const EdgeInsets.only(left: 3),
                              decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3)),
                            ),
                          Text(' mais', style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SectionTitle('Resumo do período'),
                PaceCard(
                  child: StatGrid(columns: 2, spacing: 18, children: bike
                      ? [
                          _Cmp(label: 'Pedais', value: '${cur.count}', ratio: _ch(cur.count, prev?.count)),
                          _Cmp(label: 'Tempo pedalando', value: Fmt.durationLong(cur.movingSec), ratio: _ch(cur.movingSec, prev?.movingSec)),
                          _Cmp(
                            label: 'Velocidade média',
                            value: '${Fmt.speed(cur.avgSpeed)} km/h',
                            ratio: (cur.avgSpeed != null && prev?.avgSpeed != null) ? Periods.change(cur.avgSpeed!, prev!.avgSpeed!) : null,
                          ),
                          _Cmp(label: 'Melhor média', value: cur.bestPace == null ? '—' : '${Fmt.kmh(3600 / cur.bestPace!)} km/h'),
                          _Cmp(label: 'Maior distância', value: Fmt.kmUnit(cur.longestM)),
                          _Cmp(label: 'Maior duração', value: Fmt.duration(cur.longestSec)),
                          _Cmp(label: 'Dias ativos', value: '${cur.activeDays}'),
                          _Cmp(label: 'Elevação acumulada', value: '${Fmt.integer(cur.elevGain)} m'),
                          _Cmp(label: 'Calorias (estim.)', value: '${Fmt.integer(cur.calories)} kcal'),
                        ]
                      : [
                    _Cmp(label: 'Corridas', value: '${cur.count}', ratio: _ch(cur.count, prev?.count)),
                    _Cmp(label: 'Tempo correndo', value: Fmt.durationLong(cur.movingSec), ratio: _ch(cur.movingSec, prev?.movingSec)),
                    _Cmp(
                      label: 'Pace médio',
                      value: Fmt.paceUnit(cur.avgPace),
                      ratio: (cur.avgPace != null && prev?.avgPace != null) ? Periods.change(cur.avgPace!, prev!.avgPace!) : null,
                      higherIsBetter: false,
                    ),
                    _Cmp(label: 'Velocidade média', value: '${Fmt.speed(cur.avgSpeed)} km/h'),
                    _Cmp(label: 'Maior distância', value: Fmt.kmUnit(cur.longestM)),
                    _Cmp(label: 'Maior duração', value: Fmt.duration(cur.longestSec)),
                    _Cmp(label: 'Melhor pace médio', value: Fmt.paceUnit(cur.bestPace)),
                    _Cmp(label: 'Dias ativos', value: '${cur.activeDays}'),
                    _Cmp(label: 'Elevação acumulada', value: '${Fmt.integer(cur.elevGain)} m'),
                    _Cmp(label: 'Calorias (estim.)', value: '${Fmt.integer(cur.calories)} kcal'),
                  ]),
                ),
                if (prev != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _p == EvoPeriod.year
                        ? 'Comparação com ${_year - 1}${stop.year == _year ? ' até o mesmo dia' : ''}.'
                        : 'Comparação com os ${_labels[_p]} anteriores (${Fmt.dayMonth(start.subtract(span))} a '
                            '${Fmt.dayMonth(start.subtract(const Duration(days: 1)))}).',
                    style: const TextStyle(fontSize: 12, color: PaceColors.muted),
                  ),
                ],
                const SectionTitle('Desde o início'),
                PaceCard(
                  child: StatGrid(columns: 3, children: [
                    StatTile(label: bike ? 'Pedais' : 'Corridas', value: Fmt.integer(life.count)),
                    StatTile(label: 'Distância', value: Fmt.integer(life.distanceM / 1000), unit: 'km'),
                    StatTile(label: 'Tempo', value: Fmt.durationLong(life.movingSec)),
                  ]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static List<int> _years(List<Activity> acts) {
    final s = {DateTime.now().year, for (final a in acts) a.start.toLocal().year}.toList()..sort((a, b) => b.compareTo(a));
    return s;
  }

  static Map<DateTime, double> _kmByDay(List<Activity> acts) {
    final m = <DateTime, double>{};
    for (final a in acts) {
      final l = a.start.toLocal();
      final d = DateTime(l.year, l.month, l.day);
      m[d] = (m[d] ?? 0) + a.distanceM / 1000;
    }
    return m;
  }

  static double? _ch(num cur, num? prev) => prev == null ? null : Periods.change(cur.toDouble(), prev.toDouble());
}

class _Cmp extends StatelessWidget {
  final String label;
  final String value;
  final double? ratio;
  final bool higherIsBetter;

  const _Cmp({required this.label, required this.value, this.ratio, this.higherIsBetter = true});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: 2),
        Row(
          children: [
            Flexible(
              child: Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            ),
            if (ratio != null) ...[
              const SizedBox(width: 6),
              ChangeBadge(ratio: ratio, higherIsBetter: higherIsBetter),
            ],
          ],
        ),
      ],
    );
  }
}

/// Atalhos para Recordes, Conquistas e Planos.
class _Shortcuts extends StatelessWidget {
  final AppState app;
  const _Shortcuts({required this.app});

  @override
  Widget build(BuildContext context) {
    final r5 = app.records.byKey('effort_5000');
    final badges = app.badges;
    final got = badges.where((b) => b.unlocked).length;
    final plan = app.plan;
    void open(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));
    Widget tile(IconData icon, Color c, String title, String value, String sub, Widget page) => Expanded(
          child: GlassCard(
            radius: 20,
            padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
            onTap: () => open(page),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: c, size: 22),
                const SizedBox(height: 8),
                Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: const Pal(true).muted)),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value, style: numStyle(18, color: Colors.white)),
                ),
                Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: const Pal(true).muted)),
              ],
            ),
          ),
        );
    return Row(
      children: [
        tile(Icons.emoji_events_rounded, const Color(0xFFFFC53D), 'Recordes', r5 == null ? '—' : recordValue(r5),
            r5 == null ? 'Melhor 5 km' : 'Melhor 5 km', const RecordsScreen()),
        const SizedBox(width: 10),
        tile(Icons.military_tech_rounded, const Color(0xFFB794F6), 'Conquistas', '$got/${badges.length}', 'medalhas',
            const AchievementsScreen()),
        const SizedBox(width: 10),
        tile(Icons.event_note_rounded, PaceColors.mintBright, 'Plano',
            plan?.plan == null ? 'Escolher' : '${plan!.done.length}/${plan.plan!.sessions.length}',
            plan?.plan == null ? 'de treino' : plan!.plan!.name, const PlansScreen()),
      ],
    );
  }
}

/// Chip "Ano" que abre a lista de anos com corridas.
class _YearChip extends StatelessWidget {
  final List<int> years;
  final bool selected;
  final int year;
  final ValueChanged<int> onPick;
  const _YearChip({required this.years, required this.selected, required this.year, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: 'Escolher ano',
      onSelected: onPick,
      itemBuilder: (_) => [for (final y in years) CheckedPopupMenuItem(value: y, checked: selected && y == year, child: Text('$y'))],
      child: IgnorePointer(
        child: ChoiceChip(
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [Text(selected ? '$year' : 'Ano'), const Icon(Icons.arrow_drop_down, size: 18)],
          ),
          selected: selected,
          onSelected: (_) {},
        ),
      ),
    );
  }
}
