import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../domain/models.dart';
import '../../domain/stats.dart';
import '../../state/app_state.dart';
import '../shell.dart';
import '../widgets/common.dart';
import '../widgets/guara.dart';
import '../widgets/pace_ui.dart';
import '../widgets/route_widgets.dart';
import '../widgets/run_calendar.dart';
import 'activity_detail_screen.dart';
import 'import_screen.dart';

enum _Dist { all, upTo5, from5to10, from10to21, over21 }

enum _Source { all, recorded, imported }

enum _Sort { recent, oldest, longest, fastest, longestTime }

/// Histórico: busca, filtros (período, ano, mês, distância, tipo, origem), ordenação,
/// lista agrupada por mês e calendário.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  /// 'all', 'd30', 'd90', 'm12' ou 'y2025'.
  String _period = 'all';
  int? _month; // 1..12 dentro do ano escolhido
  _Dist _dist = _Dist.all;
  String? _type;
  Sport? _sportF; // nulo = corridas e pedais
  _Source _source = _Source.all;
  _Sort _sort = _Sort.recent;
  String _query = '';
  bool _calendar = false;
  bool _searching = false;
  final _search = TextEditingController();

  static const _distLabels = {
    _Dist.all: 'Qualquer distância',
    _Dist.upTo5: 'Até 5 km',
    _Dist.from5to10: '5 a 10 km',
    _Dist.from10to21: '10 a 21 km',
    _Dist.over21: 'Acima de 21 km',
  };
  static const _sourceLabels = {_Source.all: 'Todas', _Source.recorded: 'Gravadas no PACE', _Source.imported: 'Importadas'};
  static const _sortLabels = {
    _Sort.recent: 'Mais recentes',
    _Sort.oldest: 'Mais antigas',
    _Sort.longest: 'Mais longas',
    _Sort.longestTime: 'Mais tempo',
    _Sort.fastest: 'Mais rápidas',
  };
  static const _months = ['Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun', 'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'];

  int? get _year => _period.startsWith('y') ? int.tryParse(_period.substring(1)) : null;

  String get _periodLabel => switch (_period) {
        'all' => 'Todo o período',
        'd30' => 'Últimos 30 dias',
        'd90' => 'Últimos 90 dias',
        'm12' => 'Últimos 12 meses',
        _ => _month == null ? '$_year' : '${_months[_month! - 1]}/$_year',
      };

  int get _activeFilters =>
      (_period != 'all' ? 1 : 0) +
      (_dist != _Dist.all ? 1 : 0) +
      (_type != null ? 1 : 0) +
      (_sportF != null ? 1 : 0) +
      (_source != _Source.all ? 1 : 0) +
      (_query.isNotEmpty ? 1 : 0);

  void _clear() => setState(() {
        _period = 'all';
        _month = null;
        _dist = _Dist.all;
        _type = null;
        _sportF = null;
        _source = _Source.all;
        _query = '';
        _search.clear();
        _searching = false;
      });

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(Activity a, DateTime now) {
    final l = a.start.toLocal();
    final y = _year;
    final okPeriod = switch (_period) {
      'all' => true,
      'd30' => l.isAfter(now.subtract(const Duration(days: 30))),
      'd90' => l.isAfter(now.subtract(const Duration(days: 90))),
      'm12' => l.isAfter(DateTime(now.year - 1, now.month, now.day)),
      _ => l.year == y && (_month == null || l.month == _month),
    };
    if (!okPeriod) return false;
    final km = a.distanceM / 1000;
    final okDist = switch (_dist) {
      _Dist.all => true,
      _Dist.upTo5 => km < 5,
      _Dist.from5to10 => km >= 5 && km < 10,
      _Dist.from10to21 => km >= 10 && km < 21,
      _Dist.over21 => km >= 21,
    };
    if (!okDist) return false;
    if (_sportF != null && a.sport != _sportF) return false;
    if (_type != null && a.type != _type) return false;
    if (_source == _Source.recorded && a.source != ActivitySource.recorded) return false;
    if (_source == _Source.imported && a.source == ActivitySource.recorded) return false;
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      final hay = '${a.sport.label} ${a.type} ${a.notes} ${Fmt.date(a.start)} ${Fmt.weekdayDate(a.start)} ${Fmt.km(a.distanceM)}'.toLowerCase();
      if (!hay.contains(q)) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final now = DateTime.now();
    final all = app.allActivities;
    final list = all.where((a) => _matches(a, now)).toList();
    switch (_sort) {
      case _Sort.recent:
        break;
      case _Sort.oldest:
        list.sort((a, b) => a.start.compareTo(b.start));
      case _Sort.longest:
        list.sort((a, b) => b.distanceM.compareTo(a.distanceM));
      case _Sort.longestTime:
        list.sort((a, b) => b.movingSec.compareTo(a.movingSec));
      case _Sort.fastest:
        list.removeWhere((a) => a.distanceM < 1000 || a.paceSecPerKm == null);
        // Ranking por modalidade: pedal pela velocidade; corrida pelo pace.
        if (_sportF == Sport.bike) {
          list.sort((a, b) => a.paceSecPerKm!.compareTo(b.paceSecPerKm!));
        } else {
          list.removeWhere((a) => a.isBike);
          list.sort((a, b) => a.paceSecPerKm!.compareTo(b.paceSecPerKm!));
        }
    }
    final total = PeriodStats.of(list);
    final years = {for (final a in all) a.start.toLocal().year}.toList()..sort((a, b) => b.compareTo(a));
    final types = {for (final a in all) if (_sportF == null || a.sport == _sportF) a.type}.toList()..sort();
    final byDate = _sort == _Sort.recent || _sort == _Sort.oldest;
    final recordIds = {for (final r in app.records.list) if (r.activityId != null) r.activityId!};

    // Grupos: por mês quando ordenado por data; senão, ranking em blocos de 20.
    final groups = <({String title, String sub, List<Activity> items})>[];
    if (byDate) {
      DateTime? cur;
      for (final a in list) {
        final m = Periods.monthStart(a.start.toLocal());
        if (m != cur) {
          groups.add((title: Fmt.monthYear(m), sub: '', items: []));
          cur = m;
        }
        groups.last.items.add(a);
      }
    } else {
      for (var i = 0; i < list.length; i += 20) {
        groups.add((title: i == 0 ? _sortLabels[_sort]! : '', sub: '', items: list.sublist(i, (i + 20).clamp(0, list.length))));
      }
    }

    void open(Activity a) => Navigator.push(context, MaterialPageRoute(builder: (_) => ActivityDetailScreen(activityId: a.id!)));

    return Scaffold(
      body: Stack(
        children: [
          const Positioned(top: 0, left: 0, right: 0, child: MeshBackground(height: 520)),
          SafeArea(
            bottom: false,
            child: all.isEmpty
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
                          padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
                          child: ScreenTitle(
                            'Histórico',
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!_calendar)
                                  IconButton(
                                    tooltip: 'Buscar',
                                    icon: Icon(_searching ? Icons.search_off_rounded : Icons.search_rounded),
                                    onPressed: () => setState(() {
                                      _searching = !_searching;
                                      if (!_searching) {
                                        _query = '';
                                        _search.clear();
                                      }
                                    }),
                                  ),
                                IconButton(
                                  tooltip: _calendar ? 'Ver em lista' : 'Ver calendário',
                                  icon: Icon(_calendar ? Icons.view_list_rounded : Icons.calendar_month_rounded),
                                  onPressed: () => setState(() => _calendar = !_calendar),
                                ),
                                IconButton(
                                  tooltip: 'Importar histórico',
                                  icon: const Icon(Icons.upload_file),
                                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ImportScreen())),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (_calendar)
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 6, 16, 130),
                          sliver: SliverToBoxAdapter(child: RunCalendar(activities: all)),
                        )
                      else ...[
                        if (_searching)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                              child: TextField(
                                controller: _search,
                                autofocus: true,
                                onChanged: (v) => setState(() => _query = v.trim()),
                                decoration: InputDecoration(
                                  hintText: 'Buscar por data, tipo ou observação',
                                  prefixIcon: const Icon(Icons.search_rounded),
                                  filled: true,
                                  fillColor: Colors.white.withValues(alpha: 0.9),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                          ),
                        SliverToBoxAdapter(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                            child: Row(
                              children: [
                                _MenuChip<String>(
                                  icon: Icons.event_rounded,
                                  label: _periodLabel,
                                  active: _period != 'all',
                                  items: [
                                    ('all', 'Todo o período'),
                                    ('d30', 'Últimos 30 dias'),
                                    ('d90', 'Últimos 90 dias'),
                                    ('m12', 'Últimos 12 meses'),
                                    for (final y in years) ('y$y', 'Ano de $y'),
                                  ],
                                  onPick: (v) => setState(() {
                                    _period = v;
                                    _month = null;
                                  }),
                                ),
                                if (_year != null)
                                  _MenuChip<int>(
                                    icon: Icons.calendar_view_month_rounded,
                                    label: _month == null ? 'Todos os meses' : _months[_month! - 1],
                                    active: _month != null,
                                    items: [
                                      (0, 'Todos os meses'),
                                      for (var m = 1; m <= 12; m++)
                                        if (all.any((a) {
                                          final l = a.start.toLocal();
                                          return l.year == _year && l.month == m;
                                        }))
                                          (m, _months[m - 1]),
                                    ],
                                    onPick: (v) => setState(() => _month = v == 0 ? null : v),
                                  ),
                                if (app.rides.isNotEmpty)
                                  _MenuChip<int>(
                                    icon: _sportF == Sport.bike ? Icons.directions_bike_rounded : Icons.directions_run_rounded,
                                    label: _sportF == null ? 'Corrida e pedal' : _sportF!.label,
                                    active: _sportF != null,
                                    items: const [(0, 'Corrida e pedal'), (1, 'Só corridas'), (2, 'Só pedais')],
                                    onPick: (v) => setState(() {
                                      _sportF = v == 0 ? null : (v == 1 ? Sport.run : Sport.bike);
                                      _type = null;
                                    }),
                                  ),
                                _MenuChip<_Dist>(
                                  icon: Icons.straighten_rounded,
                                  label: _distLabels[_dist]!,
                                  active: _dist != _Dist.all,
                                  items: [for (final e in _distLabels.entries) (e.key, e.value)],
                                  onPick: (v) => setState(() => _dist = v),
                                ),
                                if (types.length > 1)
                                  _MenuChip<String>(
                                    icon: Icons.category_outlined,
                                    label: _type ?? 'Todos os tipos',
                                    active: _type != null,
                                    items: [('', 'Todos os tipos'), for (final t in types) (t, t)],
                                    onPick: (v) => setState(() => _type = v.isEmpty ? null : v),
                                  ),
                                _MenuChip<_Source>(
                                  icon: Icons.source_outlined,
                                  label: _sourceLabels[_source]!,
                                  active: _source != _Source.all,
                                  items: [for (final e in _sourceLabels.entries) (e.key, e.value)],
                                  onPick: (v) => setState(() => _source = v),
                                ),
                                _MenuChip<_Sort>(
                                  icon: Icons.swap_vert_rounded,
                                  label: _sortLabels[_sort]!,
                                  active: _sort != _Sort.recent,
                                  items: [for (final e in _sortLabels.entries) (e.key, e.value)],
                                  onPick: (v) => setState(() => _sort = v),
                                ),
                                if (_activeFilters > 0)
                                  TextButton.icon(
                                    onPressed: _clear,
                                    icon: const Icon(Icons.close_rounded, size: 18),
                                    label: const Text('Limpar'),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                            child: _Summary(total: total, list: list),
                          ),
                        ),
                        if (list.isEmpty)
                          SliverToBoxAdapter(
                            child: EmptyState(
                              icon: Icons.filter_alt_off,
                              art: const Guara(pose: GuaraPose.sleep, size: 110),
                              title: 'Nada encontrado',
                              message: 'Nenhum treino com esses filtros.',
                              actions: [OutlinedButton(onPressed: _clear, child: const Text('Limpar filtros'))],
                            ),
                          ),
                        SliverList.builder(
                          itemCount: groups.length,
                          itemBuilder: (context, gi) {
                            final g = groups[gi];
                            final st = byDate ? PeriodStats.of(g.items) : null;
                            final offset = byDate ? 0 : gi * 20;
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (g.title.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                                      child: Row(
                                        children: [
                                          Expanded(child: Text(g.title, style: numStyle(17, color: Pal.of(context).ink))),
                                          if (st != null)
                                            Text(
                                              '${Fmt.kmUnit(st.distanceM, decimals: 1)} · ${_countLabel(g.items)}',
                                              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Pal.of(context).muted),
                                            ),
                                        ],
                                      ),
                                    ),
                                  GlassCard(
                                    radius: 22,
                                    padding: const EdgeInsets.symmetric(vertical: 4),
                                    child: Column(
                                      children: [
                                        for (final (i, a) in g.items.indexed) ...[
                                          if (i > 0) Divider(height: 1, indent: 76, color: Colors.white.withValues(alpha: 0.07)),
                                          _RunRow(
                                            a: a,
                                            rank: byDate ? null : offset + i + 1,
                                            record: recordIds.contains(a.id),
                                            onTap: () => open(a),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 130)),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Resumo do que está filtrado.
class _Summary extends StatelessWidget {
  final PeriodStats total;
  final List<Activity> list;
  const _Summary({required this.total, required this.list});

  @override
  Widget build(BuildContext context) {
    final bikes = list.where((a) => a.isBike).toList();
    final runs = list.where((a) => !a.isBike).toList();
    // Só pedais: velocidade média. Com corridas: pace médio só das corridas.
    final onlyBike = runs.isEmpty && bikes.isNotEmpty;
    final b = PeriodStats.of(bikes);
    final items = [
      (Fmt.integer(total.count), _countWord(list)),
      (Fmt.km(total.distanceM, decimals: total.distanceM >= 1000000 ? 0 : 1), 'km'),
      (Fmt.durationLong(total.movingSec), 'tempo'),
      onlyBike
          ? (Fmt.kmh(b.movingSec > 0 ? b.distanceM / b.movingSec * 3.6 : null), 'km/h média')
          : (Fmt.pace(PeriodStats.of(runs).avgPace), bikes.isEmpty ? 'pace médio' : 'pace (corridas)'),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [PaceColors.mintBright, PaceColors.mint, PaceColors.mintDark],
        ),
        boxShadow: [BoxShadow(color: PaceColors.mint.withValues(alpha: 0.3), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: Row(
        children: [
          for (final (i, e) in items.indexed) ...[
            if (i > 0) Container(width: 1, height: 30, color: Colors.white.withValues(alpha: 0.25)),
            Expanded(
              child: Column(
                children: [
                  FittedBox(fit: BoxFit.scaleDown, child: Text(e.$1, style: numStyle(20, color: Colors.white))),
                  const SizedBox(height: 2),
                  Text(e.$2, style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.9), fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Uma corrida na lista (sobre o vidro escuro).
class _RunRow extends StatelessWidget {
  final Activity a;
  final int? rank;
  final bool record;
  final VoidCallback onTap;
  const _RunRow({required this.a, required this.onTap, this.rank, this.record = false});

  @override
  Widget build(BuildContext context) {
    const p = Pal(true);
    final l = a.start.toLocal();
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                RouteThumbnail(points: a.previewPoints, size: 50, strokeWidth: 2, color: PaceColors.mintBright),
                if (rank != null)
                  Positioned(
                    left: -4,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(color: PaceColors.mintBright, borderRadius: BorderRadius.circular(8)),
                      child: Text('$rank', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: PaceColors.ink)),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text.rich(TextSpan(children: [
                        TextSpan(text: Fmt.km(a.distanceM), style: numStyle(18, color: Colors.white)),
                        TextSpan(text: ' km', style: TextStyle(fontSize: 12, color: p.muted, fontWeight: FontWeight.w700)),
                      ])),
                      if (record) ...[
                        const SizedBox(width: 6),
                        const Tooltip(
                          message: 'Detém um recorde',
                          child: Icon(Icons.emoji_events_rounded, size: 15, color: Color(0xFFFFC53D)),
                        ),
                      ],
                      if (a.isBike) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.directions_bike_rounded, size: 15, color: PaceColors.mintBright),
                      ],
                      if (a.source != ActivitySource.recorded) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.file_download_outlined, size: 14, color: p.muted),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${Fmt.weekdayShort(l)}, ${Fmt.dayMonth(l)}${rank != null ? '/${l.year}' : ''} · ${Fmt.time(a.start)} · ${a.type}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: p.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(Fmt.duration(a.movingSec), style: numStyle(15, color: Colors.white)),
                const SizedBox(height: 2),
                Text(Fmt.effort(a.paceSecPerKm, bike: a.isBike), style: TextStyle(fontSize: 12, color: p.muted, fontWeight: FontWeight.w600)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Filtro em forma de pílula que abre um menu.
class _MenuChip<T> extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final List<(T, String)> items;
  final ValueChanged<T> onPick;
  const _MenuChip({required this.icon, required this.label, required this.active, required this.items, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: PopupMenuButton<T>(
        tooltip: label,
        onSelected: onPick,
        itemBuilder: (_) => [for (final (v, t) in items) PopupMenuItem(value: v, child: Text(t))],
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          decoration: BoxDecoration(
            color: active ? PaceColors.ink : Colors.white.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: active ? PaceColors.ink : const Color(0x140F172A)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: active ? PaceColors.mintBright : PaceColors.mintDark),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: active ? Colors.white : PaceColors.ink,
                  )),
              Icon(Icons.arrow_drop_down_rounded, size: 20, color: active ? Colors.white70 : PaceColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// "3 corridas", "2 pedais" ou "5 treinos".
String _countWord(List<Activity> l) {
  final bikes = l.where((a) => a.isBike).length;
  final n = l.length;
  if (bikes == 0) return n == 1 ? 'corrida' : 'corridas';
  if (bikes == n) return n == 1 ? 'pedal' : 'pedais';
  return n == 1 ? 'treino' : 'treinos';
}

String _countLabel(List<Activity> l) => '${l.length} ${_countWord(l)}';
