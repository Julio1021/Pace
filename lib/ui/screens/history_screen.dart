import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../domain/models.dart';
import '../../domain/stats.dart';
import '../../state/app_state.dart';
import '../shell.dart';
import '../widgets/activity_tile.dart';
import '../widgets/common.dart';
import '../widgets/guara.dart';
import 'activity_detail_screen.dart';
import 'import_screen.dart';

enum _Period { all, d30, d90, m12, year }

enum _Dist { all, upTo5, from5to10, from10to21, over21 }

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  _Period _period = _Period.all;
  _Dist _dist = _Dist.all;

  static const _periodLabels = {
    _Period.all: 'Todo o período',
    _Period.d30: '30 dias',
    _Period.d90: '90 dias',
    _Period.m12: '12 meses',
    _Period.year: 'Este ano',
  };

  static const _distLabels = {
    _Dist.all: 'Qualquer distância',
    _Dist.upTo5: 'Até 5 km',
    _Dist.from5to10: '5 a 10 km',
    _Dist.from10to21: '10 a 21 km',
    _Dist.over21: 'Acima de 21 km',
  };

  bool _matches(Activity a, DateTime now) {
    final l = a.start.toLocal();
    final okPeriod = switch (_period) {
      _Period.all => true,
      _Period.d30 => l.isAfter(now.subtract(const Duration(days: 30))),
      _Period.d90 => l.isAfter(now.subtract(const Duration(days: 90))),
      _Period.m12 => l.isAfter(DateTime(now.year - 1, now.month, now.day)),
      _Period.year => l.year == now.year,
    };
    final km = a.distanceM / 1000;
    final okDist = switch (_dist) {
      _Dist.all => true,
      _Dist.upTo5 => km < 5,
      _Dist.from5to10 => km >= 5 && km < 10,
      _Dist.from10to21 => km >= 10 && km < 21,
      _Dist.over21 => km >= 21,
    };
    return okPeriod && okDist;
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final now = DateTime.now();
    final list = app.activities.where((a) => _matches(a, now)).toList();
    final total = PeriodStats.of(list);

    // Agrupa por mês (lista já vem do mais recente para o mais antigo).
    final rows = <Object>[];
    DateTime? curMonth;
    final monthTotals = <DateTime, PeriodStats>{};
    final byMonth = <DateTime, List<Activity>>{};
    for (final a in list) {
      final m = Periods.monthStart(a.start.toLocal());
      byMonth.putIfAbsent(m, () => []).add(a);
    }
    byMonth.forEach((k, v) => monthTotals[k] = PeriodStats.of(v));
    for (final a in list) {
      final m = Periods.monthStart(a.start.toLocal());
      if (m != curMonth) {
        rows.add(m);
        curMonth = m;
      }
      rows.add(a);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Histórico'),
        actions: [
          IconButton(
            tooltip: 'Importar histórico',
            icon: const Icon(Icons.upload_file),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ImportScreen())),
          ),
        ],
      ),
      body: app.activities.isEmpty
          ? Center(
              child: SingleChildScrollView(
                child: EmptyState(
                  icon: Icons.history,
                  art: const Guara(pose: GuaraPose.run, size: 150),
                  title: 'Nenhuma corrida ainda',
                  message: 'As corridas gravadas e importadas aparecem aqui, organizadas por mês.',
                  actions: [
                    FilledButton.icon(
                      onPressed: () => HomeShell.of(context)?.go(2),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Correr agora'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ImportScreen())),
                      icon: const Icon(Icons.upload_file),
                      label: const Text('Importar .tcx / .gpx'),
                    ),
                  ],
                ),
              ),
            )
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Row(
                      children: [
                        Expanded(child: _FilterButton<_Period>(
                          icon: Icons.calendar_month,
                          value: _period,
                          labels: _periodLabels,
                          onChanged: (v) => setState(() => _period = v),
                        )),
                        const SizedBox(width: 8),
                        Expanded(child: _FilterButton<_Dist>(
                          icon: Icons.straighten,
                          value: _dist,
                          labels: _distLabels,
                          onChanged: (v) => setState(() => _dist = v),
                        )),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [PaceColors.mint, PaceColors.mintDark],
                        ),
                        boxShadow: [BoxShadow(color: PaceColors.mint.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 8))],
                      ),
                      child: Row(
                        children: [
                          for (final e in [
                            (Fmt.integer(total.count), total.count == 1 ? 'corrida' : 'corridas'),
                            (Fmt.integer(total.distanceM / 1000), 'km'),
                            (Fmt.durationLong(total.movingSec), 'tempo'),
                          ])
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  FittedBox(fit: BoxFit.scaleDown, child: Text(e.$1, style: numStyle(24, color: Colors.white))),
                                  Text(e.$2, style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.85))),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (list.isEmpty)
                  SliverToBoxAdapter(
                    child: EmptyState(
                      icon: Icons.filter_alt_off,
                      title: 'Nada com esses filtros',
                      message: 'Mude o período ou a faixa de distância.',
                    ),
                  ),
                SliverList.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, i) {
                    final r = rows[i];
                    if (r is DateTime) {
                      final s = monthTotals[r]!;
                      return Container(
                        padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
                        child: Row(
                          children: [
                            Expanded(child: Text(Fmt.monthYear(r), style: numStyle(18, color: cs.onSurface))),
                            Text('${Fmt.kmUnit(s.distanceM, decimals: 1)} · ${s.count} '
                                '${s.count == 1 ? 'corrida' : 'corridas'}',
                                style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      );
                    }
                    final a = r as Activity;
                    return ActivityListTile(
                      activity: a,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => ActivityDetailScreen(activityId: a.id!)),
                      ),
                    );
                  },
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 130)),
              ],
            ),
    );
  }
}

class _FilterButton<T> extends StatelessWidget {
  final IconData icon;
  final T value;
  final Map<T, String> labels;
  final ValueChanged<T> onChanged;

  const _FilterButton({required this.icon, required this.value, required this.labels, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopupMenuButton<T>(
      initialValue: value,
      onSelected: onChanged,
      itemBuilder: (_) => [
        for (final e in labels.entries) PopupMenuItem(value: e.key, child: Text(e.value)),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            Icon(icon, size: 18, color: cs.primary),
            const SizedBox(width: 6),
            Expanded(child: Text(labels[value]!, maxLines: 1, overflow: TextOverflow.ellipsis)),
            Icon(Icons.arrow_drop_down, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
