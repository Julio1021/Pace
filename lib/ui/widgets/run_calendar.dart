import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../domain/models.dart';
import '../../domain/stats.dart';
import '../screens/activity_detail_screen.dart';
import 'activity_tile.dart';
import 'pace_ui.dart';

/// Calendário mensal: cada dia com corrida ganha um círculo do tamanho da distância.
class RunCalendar extends StatefulWidget {
  final List<Activity> activities;
  const RunCalendar({super.key, required this.activities});

  @override
  State<RunCalendar> createState() => _RunCalendarState();
}

class _RunCalendarState extends State<RunCalendar> {
  late DateTime _month = Periods.monthStart(DateTime.now());
  DateTime? _day;

  static const _wd = ['S', 'T', 'Q', 'Q', 'S', 'S', 'D'];

  Map<DateTime, List<Activity>> _byDay() {
    final m = <DateTime, List<Activity>>{};
    for (final a in widget.activities) {
      final l = a.start.toLocal();
      m.putIfAbsent(DateTime(l.year, l.month, l.day), () => []).add(a);
    }
    return m;
  }

  /// Semanas seguidas (até a atual ou a anterior) com pelo menos uma corrida.
  int _streak(DateTime now) {
    final weeks = {for (final a in widget.activities) Periods.weekStart(a.start.toLocal())};
    var w = Periods.weekStart(now);
    if (!weeks.contains(w)) w = DateTime(w.year, w.month, w.day - 7);
    var n = 0;
    while (weeks.contains(w)) {
      n++;
      w = DateTime(w.year, w.month, w.day - 7);
    }
    return n;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final byDay = _byDay();
    final first = widget.activities.isEmpty ? now : widget.activities.last.start.toLocal();
    final canBack = _month.isAfter(Periods.monthStart(first));
    final canFwd = _month.isBefore(Periods.monthStart(now));
    final next = DateTime(_month.year, _month.month + 1);
    final monthActs = Periods.between(widget.activities, _month, next).toList();
    final st = PeriodStats.of(monthActs);
    final maxKm = math.max(
      5.0,
      byDay.entries.where((e) => !e.key.isBefore(_month) && e.key.isBefore(next)).fold<double>(
          0, (v, e) => math.max(v, e.value.fold<double>(0, (s, a) => s + a.km))),
    );
    final lead = _month.weekday - 1; // segunda = 0
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    final cells = lead + days;
    final rows = (cells / 7).ceil();
    final selected = _day == null ? const <Activity>[] : (byDay[_day] ?? const <Activity>[]);
    final streak = _streak(now);
    const p = Pal(true);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassCard(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 14),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Mês anterior',
                    onPressed: canBack ? () => setState(() {
                              _month = DateTime(_month.year, _month.month - 1);
                              _day = null;
                            }) : null,
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(Fmt.monthYear(_month), style: numStyle(18, color: Colors.white)),
                        Text(
                          st.count == 0
                              ? 'Nenhuma corrida'
                              : '${st.count} ${st.count == 1 ? 'corrida' : 'corridas'} · ${Fmt.kmUnit(st.distanceM, decimals: 1)} · ${st.activeDays} dias ativos',
                          style: TextStyle(fontSize: 12, color: p.muted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Próximo mês',
                    onPressed: canFwd ? () => setState(() {
                              _month = next;
                              _day = null;
                            }) : null,
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  for (final w in _wd)
                    Expanded(
                      child: Center(child: Text(w, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: p.muted))),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              for (var r = 0; r < rows; r++)
                Row(
                  children: [
                    for (var c = 0; c < 7; c++)
                      Expanded(
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: () {
                            final idx = r * 7 + c - lead;
                            if (idx < 0 || idx >= days) return const SizedBox();
                            final d = DateTime(_month.year, _month.month, idx + 1);
                            final acts = byDay[d] ?? const <Activity>[];
                            final km = acts.fold<double>(0, (s, a) => s + a.km);
                            final isToday = d.year == now.year && d.month == now.month && d.day == now.day;
                            final sel = _day == d;
                            final frac = km <= 0 ? 0.0 : (0.45 + 0.55 * math.sqrt(km / maxKm)).clamp(0.45, 1.0);
                            return Semantics(
                              button: acts.isNotEmpty,
                              label: '${idx + 1}${km > 0 ? ', ${Fmt.kmUnit(km * 1000, decimals: 1)}' : ''}',
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: acts.isEmpty ? null : () => setState(() => _day = sel ? null : d),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    if (km > 0)
                                      FractionallySizedBox(
                                        widthFactor: frac * 0.92,
                                        heightFactor: frac * 0.92,
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: Color.lerp(PaceColors.mint, PaceColors.mintBright, frac)!
                                                .withValues(alpha: 0.35 + 0.6 * frac),
                                            border: sel ? Border.all(color: Colors.white, width: 2) : null,
                                          ),
                                        ),
                                      ),
                                    if (isToday && km <= 0)
                                      FractionallySizedBox(
                                        widthFactor: 0.7,
                                        heightFactor: 0.7,
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            border: Border.all(color: PaceColors.mintBright.withValues(alpha: 0.7), width: 1.5),
                                          ),
                                        ),
                                      ),
                                    Text(
                                      '${idx + 1}',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: km > 0 || isToday ? FontWeight.w800 : FontWeight.w500,
                                        color: km > 0 ? Colors.white : p.muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }(),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _Mini(
                icon: Icons.local_fire_department_rounded,
                color: const Color(0xFFFF9D5C),
                value: '$streak',
                label: streak == 1 ? 'semana seguida' : 'semanas seguidas',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Mini(
                icon: Icons.straighten_rounded,
                color: PaceColors.mintBright,
                value: st.count == 0 ? '—' : Fmt.km(st.distanceM / math.max(1, st.count), decimals: 1),
                label: 'km/corrida no mês',
              ),
            ),
          ],
        ),
        if (selected.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(Fmt.weekdayDate(selected.first.start), style: TextStyle(fontWeight: FontWeight.w800, color: Pal.of(context).ink)),
          const SizedBox(height: 6),
          for (final a in selected)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ActivityCard(
                activity: a,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ActivityDetailScreen(activityId: a.id!))),
              ),
            ),
        ] else
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text('Toque num dia marcado para ver a corrida.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Pal.of(context).muted)),
          ),
      ],
    );
  }
}

class _Mini extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  const _Mini({required this.icon, required this.color, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      radius: 18,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: numStyle(20, color: Colors.white)),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: const Pal(true).muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
